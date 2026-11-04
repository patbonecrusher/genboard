#!/bin/zsh
# Cut a direct-download release: notarized Developer ID build → GitHub release → Sparkle appcast
# on the website → Homebrew cask update.
#
#   tools/release.sh            version comes from MARKETING_VERSION in project.yml
#   tools/release.sh --dry-run  build, sign and notarize only (leaves build/Genboard-<version>.zip)
#
# Needs: a "Developer ID Application" certificate in the keychain, notarization credentials,
#        `gh` logged in, and the Homebrew tap checked out at $TAP_DIR.
#
# Environment (or ~/.config/mac-app-kit/defaults.env, then ./.release.env; both optional):
#   TEAM_ID                       Apple team id
#   TAP_DIR                       path to the patbonecrusher/homebrew-tap checkout
#   ASC_KEY_ID / ASC_ISSUER_ID    notarize with an App Store Connect API key
#                                 (the .p8 must be in ~/.appstoreconnect/private_keys), or
#   NOTARY_PROFILE                a notarytool keychain profile (default notarize-profile)
#
# The Sparkle signing key lives in the login keychain (Sparkle's generate_keys put it there).
set -euo pipefail
cd "$(dirname "$0")/.."

DRY=0; [[ ${1:-} == --dry-run ]] && DRY=1
ENV_TAP_DIR="${TAP_DIR:-}"      # a TAP_DIR set on the command line wins over the defaults files
for f in "$HOME/.config/mac-app-kit/defaults.env" ./.release.env; do [[ -f $f ]] && source "$f"; done
TAP_DIR="${ENV_TAP_DIR:-${TAP_DIR:-}}"
: "${TEAM_ID:?set TEAM_ID (Apple team id) in the environment or .release.env}"

VERSION="$(sed -nE 's/^ *MARKETING_VERSION: *"?([^"]+)"?.*/\1/p' project.yml)"
BUILD="$(sed -nE 's/^ *CURRENT_PROJECT_VERSION: *"?([^"]+)"?.*/\1/p' project.yml)"
TAG="v$VERSION"
BUILD_DIR="$PWD/build/release"
APP="$BUILD_DIR/Build/Products/Release/Genboard.app"
ZIP="$PWD/build/Genboard-$VERSION.zip"

if [[ $DRY == 0 ]]; then
  : "${TAP_DIR:?set TAP_DIR (path to the homebrew tap checkout) in the environment or .release.env}"
  if [[ -n "$(git status --porcelain)" ]]; then echo "error: working tree not clean" >&2; exit 1; fi
  if gh release view "$TAG" >/dev/null 2>&1; then echo "error: release $TAG already exists" >&2; exit 1; fi
  if grep -q "<sparkle:version>$BUILD</sparkle:version>" docs/appcast.xml 2>/dev/null; then
    echo "error: build $BUILD is already in docs/appcast.xml; bump CURRENT_PROJECT_VERSION" >&2; exit 1
  fi
fi

IDENTITY="$(security find-identity -v -p codesigning | grep 'Developer ID Application' | grep "($TEAM_ID)" | head -1 | sed -E 's/.*"(.*)".*/\1/')"
if [[ -z $IDENTITY ]]; then
  echo "error: no \"Developer ID Application\" certificate for team $TEAM_ID in the keychain." >&2
  exit 1
fi

echo "==> Building Genboard $VERSION (Release, universal)…"
xcodegen generate --quiet
rm -rf "$BUILD_DIR"
xcodebuild -project Genboard.xcodeproj -scheme Genboard -configuration Release \
  -derivedDataPath "$BUILD_DIR" -destination 'generic/platform=macOS' \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM_ID" \
  ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS="--timestamp" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  -quiet build

# Sparkle ships its helpers ad-hoc signed; notarization needs every piece signed with the
# Developer ID, the hardened runtime and a timestamp, inside-out, then the app again.
FW="$APP/Contents/Frameworks/Sparkle.framework"
SIGN=(codesign --force --sign "$IDENTITY" --options runtime --timestamp)
"${SIGN[@]}" "$FW/Versions/B/XPCServices/Installer.xpc"
"${SIGN[@]}" --preserve-metadata=entitlements "$FW/Versions/B/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$FW/Versions/B/Autoupdate"
"${SIGN[@]}" "$FW/Versions/B/Updater.app"
"${SIGN[@]}" "$FW"
"${SIGN[@]}" --preserve-metadata=entitlements "$APP"
codesign --verify --strict --deep --verbose=2 "$APP"
lipo -info "$APP/Contents/MacOS/Genboard"

echo "==> Notarizing…"
mkdir -p "${ZIP:h}"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
if [[ -n ${ASC_KEY_ID:-} ]]; then
  NOTARY_AUTH=(--key "$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")
else
  NOTARY_AUTH=(--keychain-profile "${NOTARY_PROFILE:-notarize-profile}")
fi
OUT="$(xcrun notarytool submit "$ZIP" "${NOTARY_AUTH[@]}" --wait | tee /dev/stderr)"
if ! grep -q 'status: Accepted' <<<"$OUT"; then
  ID="$(sed -nE 's/^ *id: (.*)/\1/p' <<<"$OUT" | head -1)"
  echo "error: notarization failed; the log says why:" >&2
  xcrun notarytool log "$ID" "${NOTARY_AUTH[@]}" >&2
  exit 1
fi
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"      # re-zip with the ticket stapled
spctl --assess --type execute --verbose=2 "$APP"
echo "==> Notarized: $ZIP"
[[ $DRY == 1 ]] && exit 0

echo "==> Tagging and publishing $TAG"
git tag -a "$TAG" -m "Genboard $VERSION" 2>/dev/null || true
git push origin "$TAG"
if [[ -f RELEASE_NOTES.md ]]; then
  gh release create "$TAG" "$ZIP" --title "Genboard $VERSION" --notes-file RELEASE_NOTES.md
else
  gh release create "$TAG" "$ZIP" --title "Genboard $VERSION" --generate-notes
fi

echo "==> Publishing the update to the Sparkle appcast"
SIGNATURE="$("$BUILD_DIR/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update" "$ZIP")"
python3 tools/appcast.py --version "$VERSION" --build "$BUILD" --signature "$SIGNATURE" --notes RELEASE_NOTES.md \
  --url "https://github.com/patbonecrusher/genboard/releases/download/$TAG/${ZIP:t}"
git add docs/appcast.xml
git commit -q -m "Appcast: Genboard $VERSION"
git push -q

echo "==> Updating Homebrew cask"
CASK="$TAP_DIR/Casks/genboard.rb"
SHA="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
git -C "$TAP_DIR" pull -q --rebase
sed -i '' -e "s/version \".*\"/version \"$VERSION\"/" -e "s/sha256 .*/sha256 \"$SHA\"/" "$CASK"
git -C "$TAP_DIR" add Casks/genboard.rb
git -C "$TAP_DIR" commit -q -m "Update genboard cask to v$VERSION"
git -C "$TAP_DIR" push -q
echo "==> Done. Install with: brew install --cask patbonecrusher/tap/genboard"

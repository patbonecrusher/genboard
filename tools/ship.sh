#!/bin/zsh
# Ship the next version in one go: bump the versions, check the release notes, commit, push, release.
#
#   tools/ship.sh            next minor version (0.2 → 0.3)
#   tools/ship.sh 0.2.1      a specific version
#
# RELEASE_NOTES.md must start with "Genboard <version>". If it doesn't, this writes a draft from the
# commits since the last release and stops so the notes can be edited; run it again to ship.
# The rest is tools/release.sh (notarized build, GitHub release, appcast, Homebrew cask).
set -euo pipefail
cd "$(dirname "$0")/.."

CURRENT="$(sed -nE 's/^ *MARKETING_VERSION: *"?([^"]+)"?.*/\1/p' project.yml)"
BUILD="$(sed -nE 's/^ *CURRENT_PROJECT_VERSION: *"?([^"]+)"?.*/\1/p' project.yml)"
LAST_TAG="$(git describe --tags --abbrev=0)"
APP_PATHS=(Genboard project.yml)   # changes elsewhere (tools, docs, tests) don't need a release
if [[ -n ${1:-} ]]; then
  VERSION=$1
else
  parts=(${(s:.:)CURRENT})
  VERSION="${parts[1]}.$(( ${parts[2]:-0} + 1 ))"
fi

if [[ -n "$(git status --porcelain -- ':!RELEASE_NOTES.md')" ]]; then
  echo "error: commit or stash your changes first (only RELEASE_NOTES.md may be modified)" >&2; exit 1
fi
if gh release view "v$CURRENT" >/dev/null 2>&1; then
  if [[ -z "$(git log --oneline "$LAST_TAG"..HEAD -- $APP_PATHS)" ]]; then
    echo "error: the app hasn't changed since $LAST_TAG" >&2; exit 1
  fi
  NEXT_BUILD=$(( BUILD + 1 ))
else
  # The current version was never released (an earlier ship stopped part-way): keep its numbers.
  VERSION=${1:-$CURRENT}
  NEXT_BUILD=$BUILD
fi

if [[ "$(head -1 RELEASE_NOTES.md 2>/dev/null)" != "Genboard $VERSION" ]]; then
  {
    echo "Genboard $VERSION"
    echo
    git log --reverse --format='- %s' "$LAST_TAG"..HEAD -- $APP_PATHS
    echo
    echo "Requires macOS 15 Sequoia or later, on Apple silicon or Intel."
    echo
    echo 'Homebrew: `brew upgrade --cask genboard`'
  } > RELEASE_NOTES.md
  echo "Drafted RELEASE_NOTES.md for $VERSION from the commits since $LAST_TAG."
  echo "Edit it into notes for people (what changed for them, not commit subjects), then run tools/ship.sh $VERSION again."
  exit 0
fi

echo "==> Shipping Genboard $VERSION (build $NEXT_BUILD)"
sed -i '' -E "s/^( *MARKETING_VERSION: *)\"?[^\"]+\"?/\1\"$VERSION\"/" project.yml
sed -i '' -E "s/^( *CURRENT_PROJECT_VERSION: *)\"?[^\"]+\"?/\1\"$NEXT_BUILD\"/" project.yml
git add project.yml RELEASE_NOTES.md
git commit -q -m "Genboard $VERSION" || true
git push -q
tools/release.sh

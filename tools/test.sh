#!/bin/zsh
# Runs the unit tests (GenboardTests) and prints only the results.
#   tools/test.sh                 all tests
#   tools/test.sh SearchTests     one suite
set -o pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
ONLY=(); [[ -n ${1:-} ]] && ONLY=(-only-testing:"GenboardTests/$1")
xcodebuild test -scheme Genboard -derivedDataPath build -destination 'platform=macOS' "${ONLY[@]}" 2>&1 \
  | grep -E '^\s*(✔|✘|↳)|^/.*error:|^error:|Test run with|\*\* TEST' | grep -v '✔ Test [a-zA-Z]*() passed'

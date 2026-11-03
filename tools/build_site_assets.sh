#!/bin/sh
# Regenerates the website's icons and social card in docs/ from tools/make_icon.swift.
set -e
cd "$(dirname "$0")/.."
master=$(mktemp -t genboard-icon).png
swift tools/make_icon.swift "$master"
for size in 32 64 180 512; do
    sips -z $size $size "$master" --out "docs/icon-$size.png" >/dev/null
done
swift tools/make_social_card.swift "$master" docs/social-card.png
rm "$master"
echo "Updated docs/ icons and social card"

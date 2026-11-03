#!/bin/sh
# Regenerates Genboard/Assets.xcassets/AppIcon.appiconset from tools/make_icon.swift.
set -e
cd "$(dirname "$0")/.."
out=Genboard/Assets.xcassets/AppIcon.appiconset
master=$(mktemp -t genboard-icon).png
swift tools/make_icon.swift "$master"
for size in 16 32 128 256 512; do
    sips -z $size $size "$master" --out "$out/icon_${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$master" --out "$out/icon_${size}@2x.png" >/dev/null
done
rm "$master"
echo "Updated $out"

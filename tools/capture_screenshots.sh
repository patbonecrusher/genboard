#!/bin/sh
# Captures the website screenshots from the demo project (fictional people, in-memory store, so
# real data is untouched). Needs a Debug build: xcodebuild -scheme Genboard -derivedDataPath build build
set -e
cd "$(dirname "$0")/.."
app=build/Build/Products/Debug/Genboard.app/Contents/MacOS/Genboard
n=1
for shot in board tree browse; do
    "$app" -GenboardDemo YES -GenboardDemoShot $shot >/dev/null 2>&1 &
    pid=$!
    sleep 6
    window=$(swift -e 'import CoreGraphics
let pid = Int32(CommandLine.arguments[1])!
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in windows where (w["kCGWindowOwnerPID"] as? Int32) == pid && (w["kCGWindowLayer"] as? Int) == 0 {
    print(w["kCGWindowNumber"]!); break
}' $pid)
    screencapture -x -o -l "$window" "docs/screenshot-$n.png"
    kill $pid; wait $pid 2>/dev/null || true
    sips -Z 2400 "docs/screenshot-$n.png" >/dev/null
    n=$((n + 1))
    sleep 1
done
echo "Updated docs/screenshot-1..3.png"

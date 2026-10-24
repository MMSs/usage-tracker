#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
bundle="$root/build/Usage Tracker.app"

swift build --configuration release --package-path "$root"
rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$root/Resources/Info.plist" "$bundle/Contents/Info.plist"
[[ -f "$root/Resources/AppIcon.icns" ]] && cp "$root/Resources/AppIcon.icns" "$bundle/Contents/Resources/AppIcon.icns"
cp "$root/.build/release/UsageTracker" "$bundle/Contents/MacOS/UsageTracker"
touch "$bundle"
echo "Built $bundle"

#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
bundle="$root/build/Usage Tracker.app"

swift build --configuration release --package-path "$root"
rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$root/Resources/Info.plist" "$bundle/Contents/Info.plist"
cp "$root/Resources/AppIcon.icns" "$bundle/Contents/Resources/AppIcon.icns"
cp "$root/.build/release/UsageTracker" "$bundle/Contents/MacOS/UsageTracker"
touch "$bundle"

# Sign with a stable identity when one is available, so Keychain keeps
# trusting the app across rebuilds instead of asking after each one. CI has
# no identity and ships unsigned, as the README documents.
identity="${USAGE_TRACKER_SIGNING_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"')}"
if [[ -n "$identity" ]]; then
  codesign --force --sign "$identity" --identifier com.mohab.usage-tracker "$bundle"
  echo "Signed with $identity"
else
  echo "Unsigned: no Apple Development identity found"
fi

echo "Built $bundle"

#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
bundle="$root/build/Usage Tracker.app"

swift build --configuration release --package-path "$root"
rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$root/Resources/Info.plist" "$bundle/Contents/Info.plist"

# Stamp the release version on the bundle's copy; the source Info.plist stays
# versionless so a plain build reads as a source build ("Version dev").
if [[ -n "${USAGE_TRACKER_VERSION:-}" ]]; then
  if [[ ! "$USAGE_TRACKER_VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    echo "USAGE_TRACKER_VERSION must look like 1.2.3, got: $USAGE_TRACKER_VERSION" >&2
    exit 1
  fi
  plutil -replace CFBundleShortVersionString -string "$USAGE_TRACKER_VERSION" "$bundle/Contents/Info.plist"
  plutil -replace CFBundleVersion -string "$USAGE_TRACKER_VERSION" "$bundle/Contents/Info.plist"
fi

cp "$root/Resources/AppIcon.icns" "$bundle/Contents/Resources/AppIcon.icns"
cp "$root/.build/release/UsageTracker" "$bundle/Contents/MacOS/UsageTracker"
touch "$bundle"

# Sign with a stable identity when one is available, so Keychain keeps
# trusting the app across rebuilds instead of asking after each one. CI has
# no identity and ships unsigned, as the README documents.
identity="${USAGE_TRACKER_SIGNING_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"')}"
if [[ -n "$identity" ]]; then
  codesign --force --sign "$identity" --identifier com.mohabsam.usage-tracker "$bundle"
  echo "Signed with $identity"
else
  echo "Unsigned: no Apple Development identity found"
fi

echo "Built $bundle"

#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
bundle="$root/build/Usage Tracker.app"

swift build --configuration release --package-path "$root"
bin="$(swift build --configuration release --package-path "$root" --show-bin-path)"
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

  # Only a release checks for updates, against the appcast its signing key
  # vouches for; a source build carries neither and its updates stay off.
  key_file="$root/Resources/sparkle-public-ed-key.txt"
  public_key="$( [[ -f "$key_file" ]] && tr -d '[:space:]' < "$key_file" || true )"
  if [[ -z "$public_key" ]]; then
    echo "Missing Sparkle public key in $key_file" >&2
    exit 1
  fi
  plutil -replace SUFeedURL -string "https://github.com/MMSs/usage-tracker/releases/latest/download/appcast.xml" "$bundle/Contents/Info.plist"
  plutil -replace SUPublicEDKey -string "$public_key" "$bundle/Contents/Info.plist"
  plutil -replace SUEnableAutomaticChecks -bool true "$bundle/Contents/Info.plist"
fi

cp "$root/Resources/AppIcon.icns" "$bundle/Contents/Resources/AppIcon.icns"
cp "$bin/UsageTracker" "$bundle/Contents/MacOS/UsageTracker"

# Embed Sparkle and point the executable at it.
mkdir -p "$bundle/Contents/Frameworks"
ditto "$bin/Sparkle.framework" "$bundle/Contents/Frameworks/Sparkle.framework"
if ! otool -l "$bundle/Contents/MacOS/UsageTracker" | grep -q '@executable_path/../Frameworks'; then
  install_name_tool -add_rpath @executable_path/../Frameworks "$bundle/Contents/MacOS/UsageTracker"
fi
touch "$bundle"

# Sign with a stable identity when one is available, so Keychain keeps
# trusting the app across rebuilds instead of asking after each one. Without
# one (CI), sign ad hoc so the embedded framework and the app still form a
# valid signature. Set USAGE_TRACKER_SIGNING_IDENTITY to pick an identity, or
# to - for ad hoc. A real identity also gets the hardened runtime and a secure
# timestamp, which notarization requires.
identity="${USAGE_TRACKER_SIGNING_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"' || true)}"
identity="${identity:--}"
sign=(codesign --force --sign "$identity")
if [[ "$identity" != "-" ]]; then
  sign+=(--options runtime --timestamp)
fi

# Inside out, in the order Sparkle documents for embedding its framework.
fw="$bundle/Contents/Frameworks/Sparkle.framework"
"${sign[@]}" "$fw/Versions/B/XPCServices/Installer.xpc"
"${sign[@]}" --preserve-metadata=entitlements "$fw/Versions/B/XPCServices/Downloader.xpc"
"${sign[@]}" "$fw/Versions/B/Autoupdate"
"${sign[@]}" "$fw/Versions/B/Updater.app"
"${sign[@]}" "$fw"
"${sign[@]}" --identifier com.mohabsam.usage-tracker "$bundle"
if [[ "$identity" == "-" ]]; then
  echo "Signed ad hoc"
else
  echo "Signed with $identity"
fi

echo "Built $bundle"

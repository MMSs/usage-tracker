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

# Sparkle's MIT license asks for its notice in every copy, and the framework
# doesn't carry one, so ship the text from the downloaded release.
sparkle_license="$root/.build/artifacts/sparkle/Sparkle/LICENSE"
if [[ ! -f "$sparkle_license" ]]; then
  echo "Missing Sparkle's license at $sparkle_license" >&2
  exit 1
fi
cp "$sparkle_license" "$bundle/Contents/Resources/Sparkle-LICENSE.txt"
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

# iCloud sync needs a provisioning profile granting the iCloud container,
# push and keychain sharing. With USAGE_TRACKER_PROVISIONING_PROFILE set, the
# profile is embedded and the app is signed with entitlements derived from
# it; without one the app runs as before and says sync isn't available.
entitlements=()
profile="${USAGE_TRACKER_PROVISIONING_PROFILE:-}"
if [[ -n "$profile" ]]; then
  if [[ "$identity" == "-" ]]; then
    echo "A provisioning profile needs a signing identity, not ad hoc signing" >&2
    exit 1
  fi
  cp "$profile" "$bundle/Contents/embedded.provisionprofile"

  decoded="$root/build/profile.plist"
  plist="$root/build/UsageTracker.entitlements"
  security cms -D -i "$profile" > "$decoded"
  /usr/libexec/PlistBuddy -x -c "Print :Entitlements" "$decoded" > "$plist"
  app_id="$(/usr/libexec/PlistBuddy -c "Print :com.apple.application-identifier" "$plist")"

  # A profile grants wildcards and both environments; a signed app names
  # exactly what it uses. A release talks to the production CloudKit.
  environment=Development
  [[ -n "${USAGE_TRACKER_VERSION:-}" ]] && environment=Production
  plutil -replace com.apple.developer.icloud-container-environment -string "$environment" "$plist"
  plutil -replace com.apple.developer.icloud-services -json '["CloudKit"]' "$plist"
  plutil -replace keychain-access-groups -json "[\"$app_id\"]" "$plist"
  for unused in com.apple.developer.ubiquity-kvstore-identifier com.apple.developer.ubiquity-container-identifiers \
    com.apple.developer.icloud-container-development-container-identifiers; do
    plutil -remove "$unused" "$plist" 2>/dev/null || true
  done
  entitlements=(--entitlements "$plist")
fi

# Inside out, in the order Sparkle documents for embedding its framework.
fw="$bundle/Contents/Frameworks/Sparkle.framework"
"${sign[@]}" "$fw/Versions/B/XPCServices/Installer.xpc"
"${sign[@]}" --preserve-metadata=entitlements "$fw/Versions/B/XPCServices/Downloader.xpc"
"${sign[@]}" "$fw/Versions/B/Autoupdate"
"${sign[@]}" "$fw/Versions/B/Updater.app"
"${sign[@]}" "$fw"
"${sign[@]}" "${entitlements[@]}" --identifier com.mohabsam.usage-tracker "$bundle"
if [[ "$identity" == "-" ]]; then
  echo "Signed ad hoc"
else
  echo "Signed with $identity"
fi
if [[ -n "$profile" ]]; then
  echo "Embedded $profile; iCloud sync available"
fi

echo "Built $bundle"

#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
bundle="$root/build/Usage Tracker.app"
installed="/Applications/Usage Tracker.app"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ ! -d "$bundle" ]]; then
  echo "Build the bundle first: scripts/build-app.sh" >&2
  exit 1
fi

# Copying over a bundle that is still installed leaves LaunchServices holding a
# stale record for the path, and every later launch fails with "Launchd job
# spawn failed". Quitting, removing, and unregistering first avoids that.
pkill -f "$installed" || true

# pkill only signals; an `open` while the old copy is still exiting fails
# with error -600, so wait for it to go.
for _ in {1..50}; do
  pgrep -f "$installed" >/dev/null || break
  sleep 0.1
done

rm -rf "$installed"
"$lsregister" -u "$installed" 2>/dev/null || true

cp -R "$bundle" /Applications/
"$lsregister" -f "$installed" 2>/dev/null || true

echo "Installed $installed"

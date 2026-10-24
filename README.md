# Usage Tracker

A native macOS 26+ menu-bar app that shows AI usage and spend across Cursor,
Anthropic, and OpenAI in one place.

## Requirements

- macOS 26
- Xcode Command Line Tools

## Build and install

Build the app:
```zsh
scripts/build-app.sh
```

Install it:
```zsh
scripts/install-app.sh
open "/Applications/Usage Tracker.app"
```

If an Apple Development certificate is in your Keychain, the build script
signs the app with it. Without one the app is unsigned and macOS asks for your
Keychain password once after every rebuild, because each unsigned build looks
like a new app. Set `USAGE_TRACKER_SIGNING_IDENTITY` to pick a specific
identity.

Use the script rather than copying the bundle by hand. Copying over a copy that
is already installed leaves LaunchServices holding a stale record for the path,
and every later launch fails with `Launchd job spawn failed`.

## Setting up Cursor

Opening the app shows the Settings window; the menu bar gets one Usage
Tracker item. Pick Cursor in the sidebar, or click the menu bar item and then
Set up. Once a provider is configured it gets its own menu bar item;
unconfigured providers show nothing.

Paste the value of the `WorkosCursorSessionToken` cookie into the field. The
help button beside the field explains where to find it in your browser. The
value saves shortly after you stop typing, and only to the login Keychain.
Afterwards the field shows the first and last few characters of the saved
value so you can tell which one is in use; paste over it to replace it.

## Settings

Settings is its own window. Open it from the gear in any menu bar popover, or
by opening the app again from Finder or Spotlight. The app appears in the Dock
while the window is open and leaves when it closes. Starting at login does not
open it.

- Refresh interval: 1, 5, 15, or 60 minutes. The default is 5. Refreshing
  pauses while the Mac is asleep or offline and resumes when both are back.
- Menu bar: show text, a countdown, and a graph drawn as Rings or Bars. The
  Colored option tints the text and graph by remaining capacity or pacing.

## Status

Early development. Cursor works. Anthropic and OpenAI follow in later releases.

## Trademarks

Cursor, Anthropic, Claude and OpenAI are trademarks of their respective owners.
Usage Tracker uses the names and marks only to identify which service a menu
bar item reports on. It is not affiliated with or endorsed by any of them. The
Cursor cube is drawn from the asset pack at <https://cursor.com/brand>.

## Removal

1. Quit Usage Tracker.
2. In **System Settings > General > Login Items & Extensions**, remove Usage
   Tracker from the login items list.
3. Delete `/Applications/Usage Tracker.app`.
4. Delete the stored Cursor session token from the login Keychain:

```zsh
security delete-generic-password \
  -s "com.mohab.usage-tracker" \
  -a "cursor-session-token"
```

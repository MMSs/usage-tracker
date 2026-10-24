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

Use the script rather than copying the bundle by hand. Copying over a copy that
is already installed leaves LaunchServices holding a stale record for the path,
and every later launch fails with `Launchd job spawn failed`.

## Setting up Cursor

On first launch the menu bar shows one Usage Tracker item. Click it, then click
Set up to open Settings. Once a provider is configured it gets its own menu bar
item; unconfigured providers show nothing.

Paste the value of the `WorkosCursorSessionToken` cookie into the field. The
help button beside the field explains where to find it in your browser. The
value saves shortly after you stop typing, and only to the login Keychain.

## Settings

- Refresh interval: 1, 5, 15, or 60 minutes. The default is 5. Refreshing
  pauses while the Mac is asleep or offline and resumes when either comes back.
- Menu bar: show text, a countdown, and a graph drawn as Rings or Bars. The
  Colored option tints the text and graph by remaining capacity or pacing.

## Status

Early development. Cursor works. Anthropic and OpenAI follow in later releases.

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

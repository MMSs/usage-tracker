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

Launching the app adds one Usage Tracker item to the menu bar. Click it and
then Set up to open Settings, or open the app a second time from Applications
or Spotlight while it is running. Once a provider is configured it gets its own menu bar item;
unconfigured providers show nothing.

Paste the value of the `WorkosCursorSessionToken` cookie into the field. The
help button beside the field explains where to find it in your browser. The
value saves shortly after you stop typing, and only to the login Keychain.
Afterwards the field shows the first and last few characters of the saved
value so you can tell which one is in use; paste over it to replace it.

## Setting up Anthropic

The Anthropic tab takes two independent credentials. Each one switches on its
own half, and each half has its own Enabled switch on the tab.

- Session key: the value of the `sessionKey` cookie from claude.ai (it starts
  with `sk-ant-sid01-`). It shows your subscription meters: the 5-hour
  Session and the Weekly window, plus the per-model weekly rows, each with its
  reset time. In the menu bar they appear as `S` and `W`. Sign in to
  [claude.ai](https://claude.ai) in Chrome, press Option-Command-I, open
  Application, Cookies, claude.ai, and copy the value. Signing out of claude.ai
  in that browser invalidates the key.
- Admin key: an `sk-ant-admin...` key from
  [console.anthropic.com](https://console.anthropic.com/settings/admin-keys)
  (Settings, Admin keys). It shows API spend and a daily cost chart, with an
  optional monthly API budget that drives the ring and pacing. Only
  organization admins can create one; it reads cost data and cannot call
  models.

Without an Admin key, or with API usage switched off, only the subscription
meters appear. Both values save shortly after you stop typing, and only to the
login Keychain.

## Settings

Settings is its own window. Open it from the gear in any menu bar popover, or
by opening the app again from Applications or Spotlight while it is running.
Launching the app never opens it. The app appears in the Dock while the
window is open and leaves when it closes.

- General: the menu bar defaults for every provider. Show text, a countdown,
  and a graph drawn as Rings or Bars. Colored tints the text and graph by
  remaining capacity or pacing.
- Each provider tab: an Enabled switch (off removes the item and stops
  fetching, credentials stay), the refresh interval on a slider from 30 seconds to
  1 hour (default 5 minutes), and an optional custom appearance that overrides the defaults.
  Refreshing pauses while the Mac is asleep or offline and resumes when both
  are back.

## Troubleshooting

When a refresh fails, the menu bar item shows an error mark and the popover
says which half failed (Plan usage or API spend), why, and how to fix it. The
last successful report stays on screen, dimmed.

The app writes refreshes, HTTP responses, and scheduling to the system log
under the subsystem `com.mohabsam.usage-tracker`. Watch it live:

```zsh
log stream --predicate 'subsystem == "com.mohabsam.usage-tracker"' --level debug
```

Failures are kept, so they can be read afterwards:

```zsh
log show --last 1h --predicate 'subsystem == "com.mohabsam.usage-tracker"'
```

The log never contains credentials, cookies, headers, query strings, or
response bodies. Organization ids in paths are shown as `{uuid}`.

## Status

Early development. Cursor works. Anthropic is implemented but not yet verified
against the live services. OpenAI follows in a later release.

## Trademarks

Cursor, Anthropic, Claude and OpenAI are trademarks of their respective owners.
Usage Tracker uses the names and marks only to identify which service a menu
bar item reports on. It is not affiliated with or endorsed by any of them. The
Cursor cube is drawn from the asset pack at <https://cursor.com/brand>. The
Anthropic mark is an original "A\" drawing, not Anthropic's or Claude's logo.

## Removal

1. Quit Usage Tracker.
2. In **System Settings > General > Login Items & Extensions**, remove Usage
   Tracker from the login items list.
3. Delete `/Applications/Usage Tracker.app`.
4. Delete the stored credentials from the login Keychain:

```zsh
security delete-generic-password \
  -s "com.mohabsam.usage-tracker" \
  -a "cursor-session-token"
```

Repeat with `-a "anthropic-session-key"` and `-a "anthropic-admin-key"` for the
Anthropic credentials.

Builds before the rename used the identifier `com.mohab.usage-tracker`. The
first launch of a newer build moves their credentials and settings over. If a
move failed, the old items remain under `-s "com.mohab.usage-tracker"` and can
be deleted the same way.

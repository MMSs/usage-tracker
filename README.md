# Usage Tracker

A native macOS 26+ menu-bar app that shows AI usage and spend across Cursor,
Anthropic, and OpenAI in one place.

## Install

With Homebrew:
```zsh
brew install --cask MMSs/tap/usage-tracker
```

Or download `Usage-Tracker-<version>.zip` from the latest
[GitHub Release](https://github.com/MMSs/usage-tracker/releases/latest), unzip
it, and move the app to Applications.

It requires macOS 26 on Apple Silicon.

## Requirements

- macOS 26
- Xcode Command Line Tools

## Build from source

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
signs the app with it. Without one the app is signed ad hoc and macOS asks for
your Keychain password once after every rebuild, because each ad hoc build
looks like a new app. Set `USAGE_TRACKER_SIGNING_IDENTITY` to pick a specific
identity, or to `-` to sign ad hoc.

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
  in that browser invalidates the key. When the key belongs to more than one
  organization, an Organization picker appears under it; plan usage is not
  fetched until you choose one. Removing or replacing the key forgets the
  choice.
- Admin key: an `sk-ant-admin...` key from
  [console.anthropic.com](https://console.anthropic.com/settings/admin-keys)
  (Settings, Admin keys). It shows API spend and a daily cost chart, with an
  optional monthly API budget that drives the ring and pacing. Only
  organization admins can create one; it reads cost data and cannot call
  models.

Without an Admin key, or with API usage switched off, only the subscription
meters appear. Both values save shortly after you stop typing, and only to the
login Keychain.

## Setting up OpenAI

The OpenAI tab takes two independent credentials. Each one switches on its
own half, and each half has its own Enabled switch on the tab.

- Codex auth.json: the contents of `~/.codex/auth.json`. Run `codex login` if
  you have not already, then `cat ~/.codex/auth.json | pbcopy` and paste it
  into the field. It shows your Codex subscription meters: the Session and
  Weekly windows, each with its reset time, plus your plan name and a Credits
  row when credits have been granted. In the menu bar they appear as `S` and
  `W`.
- Admin key: an `sk-admin-...` key from
  [platform.openai.com](https://platform.openai.com/settings/organization/admin-keys)
  (Settings, Organization, Admin keys). It shows API spend and a daily cost
  chart, with an optional monthly API budget that drives the ring and pacing.

The app refreshes the pasted Codex token when it expires and keeps the renewed
token only in Keychain. Codex CLI and the app each hold their own copy of the
token, so when one refreshes it the other's copy can stop working. If Codex
asks you to log in again, or the OpenAI item shows `Expired`, run
`codex login` and paste the new `auth.json` over the saved one.

Both values save shortly after you stop typing, and only to the login
Keychain.

## Popover

Click a provider's menu bar item for its popover. Each limit row shows its
percent and reset time over a progress bar, and the main rows draw a chart on
top of that bar:

- Session: the last 24 hours of percent used, as a filled line over a
  `24h ago · 12h · now` axis. A reset drops it to zero, and time the app was
  not running stays empty.
- Weekly: one bar per 24 hours of the current weekly window, counted from
  its reset time and named under the block by the weekday it starts, each
  showing how much of the weekly limit that stretch used. The dashed
  line is an even pace (a seventh of the limit a day), bars are green at or
  under it and amber or red over it, today is brighter, and slots to come or
  before the app had samples are empty.
- API spend: one bar per day of the month. With a monthly budget the bars
  are coloured against an even daily share, the dashed line marks it, and the
  budget bar sits under them; without one they are plain and scaled to the
  largest day.
- Cursor's billing cycle: one bar per day of the cycle over the Included usage
  bar, coloured against the cycle's even daily share. A cycle with no limit
  draws plain bars scaled to the largest day, with no bar under them.

Hover a day's bar to see its date and amount. Per-model rows, Extra usage and
Credits keep their plain bars.

The buttons along the bottom (Refresh, Settings, Quit) light up on hover and
darken while pressed. Refresh (Command-R) turns into a spinner while any of
the provider's fetches runs, scheduled ones included. After a click it then
shows a green check when every half refreshed, or a red mark when one failed,
for a second and a half. A click while the spinner shows does nothing, and
closing the popover does not stop a refresh you started.

## Settings

Settings is its own window. Open it from the gear in any menu bar popover, or
by opening the app again from Applications or Spotlight while it is running.
Launching the app never opens it. The app appears in the Dock while the
window is open and leaves when it closes. Each page folds its titled sections
like an accordion: click a section's header to open it, and the one that was
open closes. The version under Updates opens About Usage Tracker, as does the
app menu while Settings is open.

- General: the menu bar defaults for every provider. Show text, a countdown,
  and a graph drawn as Rings, Bars, Battery, Gauge, Segments, Columns or
  Dials. All three can be off: the item is then just the logo (badged when a
  half fails) unless a half is loading, needs setup or has failed, and the API
  amount shows with Show text, or with the graph when there is no budget ring.
  Colored tints the text and graph by remaining capacity or pacing. Limits
  picks both windows or just the short or the long one. These sit under Menu
  bar appearance, with a separate list below of the providers that have a
  custom appearance: a name opens that provider's appearance settings, and
  Use Defaults switches its custom appearance off, keeping it for when you
  switch it back on. Open at login
  registers the app as a login item; the line under the switch shows what
  macOS reports, with a button to System Settings when it needs your approval.
- Updates: release copies check for updates automatically. The Check
  automatically switch in General > Updates turns that off, and the Check Now
  button looks straight away. Updates install in place and keep Keychain access. Builds
  made from source don't update, and the section says so.
- Each provider tab: an Enabled switch (off removes the item and stops
  fetching, credentials stay) and, on each half's tab, a Show in menu bar
  switch under that half's Enabled switch (off hides that half from the item;
  it is still fetched, alerts and shows in the panel; with both off the item is
  the logo) and its own refresh interval on a slider from 30 seconds to 1 hour
  (default 5 minutes). The
  Options tab can give the provider its own appearance in place of the defaults.
  Refreshing pauses while the Mac is asleep or offline and resumes when both
  are back.
- The provider tab's Options tab (called Menu bar before) holds that
  provider's appearance and its Alerts switch.

## Alerts

Usage Tracker sends a macOS notification when a running limit window (the
session, the weekly window, a per-model window, or Cursor's billing cycle) or
an API budget reaches 80% and again at 95%. Each threshold alerts once per
window. A new reset, or usage falling back under the threshold, re-arms it. If
usage jumps past both at once, only the 95% alert is sent.

Alerts are on by default, and macOS asks for notification permission when the
app launches. Turn them all off with General, Alerts, or pick the kinds
(Usage thresholds, Session, Refresh failures; the last is off by default) in
the rows below it. One provider can be turned off with its Options tab, Alerts.

Session posts once when a running session resets, saying you are back to 0%,
or, when Auto-start (or your own use) has already opened the next one, that a
new session started, in that same one alert. Refresh failures posts once when a
half starts failing, naming the cause, and not again until a refresh succeeds;
it never posts while the Mac is offline.

## Session start

Anthropic and OpenAI subscription windows last 5 hours and begin with your
first message. While the session is not running, the popover's Limits section
shows a Start session button. It sends the one-word message `ping` with the
cheapest model to begin the window, then refreshes. Anthropic creates a
claude.ai chat, sends the message, and deletes the chat; OpenAI makes one Codex
request.

Auto-start sessions, in the Schedule section of the provider's Subscription
tab, does the same as soon as the previous window ends. It is off by default, runs at most once per 10
minutes after any start (Start session included), only on scheduled refreshes,
and never while the credential is expired or erroring or the Subscription half
is switched off. After three starts in a row that leave the session closed, it
pauses until a refresh sees the session open; Start session still works.

The default models are `claude-haiku-5-5` for Anthropic and `gpt-6-luna` for
OpenAI. To use another model, set it and relaunch the app:

```zsh
defaults write com.mohabsam.usage-tracker sessionStart.model.openai <model id>
```

Use `sessionStart.model.anthropic` for Anthropic, and `defaults delete` on the
same key to restore the default. If claude.ai refuses its model, the app
retries once without naming one.

## Open at login

A fresh install registers itself as a login item once, on its first launch
(the renamed identifier counts as fresh). macOS lists it under **System
Settings > General > Login Items & Extensions > Open at Login**. It is not
under "Allow in the Background", because the app has no helper or agent.

Turning it off sticks, in either place: switch it off in Settings, or remove
it in System Settings, and the app does not register itself again on later
launches. Turn the Settings switch back on to restore it. Reinstalling or
moving the app can reset macOS's record of the item; the app then reads that
as "off", so turn the switch back on in Settings. If registration
fails, the error shows under the switch and in the log
(`log show --last 1h --predicate 'subsystem == "com.mohabsam.usage-tracker" AND category == "login-item"'`).

## Troubleshooting

When a refresh fails, the menu bar item shows an error mark, and a "!" badge
is cut into the provider logo (the badge stays when that half is hidden from
the menu bar). The popover says which half failed (Plan usage or API spend),
why, and how to fix it. The last successful report stays on screen, dimmed.
When a service is rate limiting requests, the popover says when the app will
retry; scheduled refreshes of that half wait until then, while Refresh still
asks right away.

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

Switching between a build from source and a release asks once per stored
credential for Keychain access, because they are signed differently. Click
**Always Allow**.

## Privacy

Usage Tracker reads usage and spend from Cursor, Anthropic, and OpenAI using
the credentials you paste. Session start, manual or auto, is the one thing that
sends a real message (`ping`) on your account. Nothing else is sent.

Checking for updates fetches the update feed from github.com; it sends nothing
about you or your usage.

## Use at your own risk

The admin keys use each provider's official API. The subscription meters do
not: they read the private endpoints behind the Cursor dashboard, claude.ai
and Codex, signed in with the cookie or token you paste. Those endpoints are
undocumented, can change without notice, and may not be allowed by the
provider's terms of service. Session start goes further and sends a real
message on your account. A provider could limit or suspend an account used
this way. Decide whether that risk is acceptable for your account before you
paste a session credential or turn on session start.

Usage Tracker is provided as is, without warranty of any kind, under the MIT
License.

## Status

Cursor, Anthropic and OpenAI all work against their live services.

## Trademarks

Cursor, Anthropic, Claude and OpenAI are trademarks of their respective owners.
Usage Tracker uses the names and marks only to identify which service a menu
bar item reports on. It is not affiliated with or endorsed by any of them. The
Cursor cube is drawn from the asset pack at <https://cursor.com/brand>, and the
OpenAI blossom from the monochrome mark OpenAI publishes at
<https://openai.com/brand>. The Anthropic mark is an original "A\" drawing, not
Anthropic's or Claude's logo.

## Third-party software

Usage Tracker includes [Sparkle](https://sparkle-project.org) for updates,
under the MIT License. Its full license text ships inside the app at
`Contents/Resources/Sparkle-LICENSE.txt`.

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
Anthropic credentials, and with `-a "openai-auth-json"` and
`-a "openai-admin-key"` for the OpenAI ones.

Builds before the rename used the identifier `com.mohab.usage-tracker`. The
first launch of a newer build moves their credentials and settings over.
Expect one Keychain prompt per stored credential then; click **Always Allow**.
If a move failed, the old items remain under `-s "com.mohab.usage-tracker"` and
can be deleted the same way.

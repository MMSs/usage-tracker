# Contributing

Thanks for helping with Usage Tracker. It is a native macOS 26+ menu-bar app
built with SwiftPM.

## Build and test

Run the tests:
```zsh
swift test
```

To try a change, build the app, install it, then open the installed copy:
```zsh
scripts/build-app.sh
scripts/install-app.sh
open "/Applications/Usage Tracker.app"
```

Open the copy in `/Applications`, not the one in `build/`. Use
`scripts/install-app.sh` rather than copying the bundle by hand; copying over an
installed copy makes later launches fail with `Launchd job spawn failed`.

Add a regression test for any behavior change.

## Pull requests

Keep each pull request to one change. PRs are squash merged, so the PR title
becomes the commit message and decides the next version number.

Titles follow this grammar:

```
<type>(<scope>)!: <summary>
```

The scope and the `!` are optional. The summary is lowercase and imperative.
Example:

```
fix: keep one popover's fade-out from cancelling another's
```

The type sets the version bump:

| Title | Bump |
| --- | --- |
| `!` after the type, such as `feat!:` | major |
| `feat` | minor |
| `fix`, `perf` | patch |
| `docs`, `ci`, `chore`, `refactor`, `test`, `build` | none |

If a PR has to bundle several changes, list each one as a bullet under a
`## Changes` heading in the description.

## Releases

The maintainer cuts releases. Merging a PR does not publish one.

# Changelog

## Unreleased

- The token is now also cached in a second Keychain item this app creates and owns, so normal operation no longer touches Claude Code's item (and therefore rarely triggers macOS's confirmation prompt at all) — only when the underlying token actually rotates. See the README's "How it works" section for the security tradeoff this involves before building it yourself.
- The app now has a proper icon (the dual-ring motif on a dark squircle), shown in Finder, the DMG, Login Items, and permission dialogs instead of the generic blank-app icon.

## v1.1.0

- Dropdown now shows per-model weekly limits (e.g. Sonnet, Fable) whenever your plan tracks one separately, in addition to the overall 5-hour and weekly numbers.
- Background refresh interval changed from 5 to 15 minutes.
- The app now reads the Keychain token once and reuses it across polls, instead of re-reading on every refresh.
- `release.sh` now builds into its own `.release-build/` directory so it can never collide with `build.sh`'s install to `/Applications`.
- Added `setup-signing.sh` to create and trust a stable local code-signing identity in one step, so rebuilds don't repeatedly prompt for your login password.

## v1.0.0

- First release: dual-ring menu bar icon (outer = 5-hour limit, inner = weekly limit), colored by severity, with a square border.
- Dropdown shows exact percentages and reset times, a manual refresh, and a Launch at Login toggle.
- Refreshes on click, on wake, and periodically in the background.
- Downloadable `.dmg`, or build from source with `build.sh`.

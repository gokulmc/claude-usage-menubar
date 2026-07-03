# Claude Usage

A tiny macOS menu bar app that shows your Claude usage at a glance — two rings, always visible, no need to open a browser tab.

![Claude Usage menu bar and dropdown](docs/hero.png)

- **Outer ring** — your 5-hour session limit
- **Inner ring** — your weekly limit
- Rings turn orange, then red, as you approach a limit
- Click the icon for exact percentages and reset times — including any per-model weekly caps (e.g. Sonnet, Fable) your plan tracks separately
- Refreshes on click, when your Mac wakes up, and every 15 minutes in the background

## Download

**[Download the latest release](https://github.com/gokulmc/claude-usage-menubar/releases/latest)** — open the `.dmg` and drag ClaudeUsage into Applications. No Xcode or Swift needed.

This build isn't notarized (no Apple Developer account behind it), so macOS will warn about an unidentified developer on first launch. Right-click the app in Applications and choose **Open** to bypass that, just once.

Prefer to build it yourself instead? See [Build from source](#build-from-source) below.

## Requirements

- macOS 13 (Ventura) or later
- [Claude Code](https://claude.com/claude-code) installed and logged in — this app reads the same OAuth credentials Claude Code stores in your macOS Keychain, so there's nothing extra to configure
- Building from source only: Xcode Command Line Tools (for the Swift compiler): `xcode-select --install`

## Build from source

```bash
git clone https://github.com/gokulmc/claude-usage-menubar.git
cd claude-usage-menubar
./setup-signing.sh   # recommended, one-time — see below
./build.sh
```

`build.sh` builds a release binary, packages it as `ClaudeUsage.app`, code-signs it, copies it to `/Applications`, and launches it. The icon should appear in your menu bar within a couple of seconds.

The first launch will ask for permission to read the `Claude Code-credentials` Keychain item — click **Always Allow**.

To update after pulling new changes, just run `./build.sh` again.

### Why `setup-signing.sh`?

`build.sh` needs a stable code-signing identity to reuse across rebuilds; without one it falls back to ad-hoc signing, and macOS will periodically ask for your login password again to re-confirm Keychain access (see [Troubleshooting](#troubleshooting) for why). `setup-signing.sh` creates and trusts a local identity (`ClaudeUsageLocalSign`) so you only ever see that prompt once. It's scoped entirely to your own login keychain — no sudo, no system-wide changes.

### Launch at login

Click the menu bar icon and check **Launch at Login** to have it start automatically every time you sign in.

### Uninstall

```bash
osascript -e 'tell application "ClaudeUsage" to quit'
rm -rf /Applications/ClaudeUsage.app
```

(If you enabled Launch at Login, also uncheck it from the app's menu first, or remove it from System Settings → General → Login Items.)

## How it works

Claude Code stores your OAuth token in the macOS Keychain under the service name `Claude Code-credentials`. This app reads that token locally and calls Anthropic's usage endpoint (`GET /api/oauth/usage`) to get your current 5-hour and weekly utilization — the same numbers Claude Code shows with `/usage`. Nothing is sent anywhere except Anthropic's API; there's no third-party server involved.

This uses an internal, undocumented API endpoint, so it could change or break without notice.

## Troubleshooting

**Menu bar item shows a gray "!" badge.** The last refresh failed — usually because Claude Code's credentials need refreshing. Open Claude Code and run any command, then click **Refresh Now** in the app's menu.

**macOS keeps asking for my login password, over and over.** Run `./setup-signing.sh` then `./build.sh`. Two different causes produce this symptom:

- *Every time you rebuild:* the app is ad-hoc signed (no `ClaudeUsageLocalSign` identity was found), so each rebuild produces a new binary hash that macOS treats as a "different app."
- *Every 30-60+ minutes, or after your Mac sleeps, even without rebuilding:* the app is signed with a self-signed certificate that isn't marked as *trusted*. macOS can't durably cache your "Always Allow" decision for an untrusted certificate, so it silently re-validates — and re-prompts — after the Keychain locks (sleep, idle timeout, etc).

`setup-signing.sh` fixes both: it creates the `ClaudeUsageLocalSign` identity if missing, and trusts it for code signing, which is the step that makes "Always Allow" actually stick.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE)

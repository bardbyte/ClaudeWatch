# ClaudeWatch

A native macOS desktop app that monitors and dispatches across multiple Claude Code CLI sessions from a single window.

Stop tab-cycling through terminals to check which Claude is done. ClaudeWatch tells you.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5-orange) ![License](https://img.shields.io/badge/license-MIT-green) ![Zero Dependencies](https://img.shields.io/badge/dependencies-0-brightgreen) [![Build](https://github.com/bardbyte/ClaudeWatch/actions/workflows/build.yml/badge.svg)](https://github.com/bardbyte/ClaudeWatch/actions/workflows/build.yml)

## What it does

- **Monitors all active Claude Code sessions** by reading `~/.claude/sessions/`
- **Shows real-time status**: Working, Needs You, Stale, Crashed, Done
- **"Tap In" dispatch** — type or speak a task and send it directly to a session's terminal
- **Wispr Flow integration** — auto-activates voice dictation on Tap In
- **Focuses the right terminal tab** — finds the exact tab by PID/TTY, not just the directory
- **macOS notifications** when a session needs your attention
- **Pin on top** for ambient monitoring while you work

## The Problem

If you run 5-20 Claude Code sessions in parallel (and you should), you have no way to know which one finished, which one is stuck waiting for input, or what any of them achieved — without manually checking every terminal tab.

ClaudeWatch replaces that polling loop with a single dashboard.

## Install

### Homebrew (recommended)

```bash
brew install --cask claudewatch
```

### Download

1. Go to [Releases](../../releases) and download `ClaudeWatch.zip`
2. Unzip and drag `ClaudeWatch.app` to Applications
3. First launch: **right-click the app → Open** (required for unsigned apps)
4. Grant Accessibility permission when prompted (needed for terminal focus)

### Build from source

```bash
git clone https://github.com/bardbyte/ClaudeWatch.git
cd ClaudeWatch
make build
make install   # copies to /Applications
```

Or manually:

```bash
chmod +x build.sh
./build.sh
open build/ClaudeWatch.app
```

Requires Xcode Command Line Tools. No other dependencies.

## How it works

ClaudeWatch reads Claude Code's session data from the filesystem:

| Source | What it provides |
|--------|-----------------|
| `~/.claude/sessions/*.json` | Active session PIDs, working directories, start times |
| `~/.claude/projects/*/*.jsonl` | Conversation logs — last message, tool actions, status |
| `ps` / `kill -0` | PID liveness checks |

**State detection logic:**
- JSONL modified <30s ago → **Working** (green)
- JSONL stale 30s-3min + last message is assistant → **Needs You** (amber)
- JSONL stale >5min + PID alive → **Stale** (yellow)
- PID dead + clean exit → **Done** (gray)
- PID dead unexpectedly → **Crashed** (red)

**Dispatch** works by finding the session's TTY device, focusing the correct Terminal.app/iTerm2 tab via AppleScript, and pasting the message.

## Features

- **Zero dependencies** — system frameworks only (SwiftUI, AppKit, UserNotifications)
- **1.3 MB** universal binary (Apple Silicon + Intel)
- **Hardened runtime** enabled
- **No network access** — everything is local filesystem reads
- **Grouped by priority** — "Needs Attention" sessions always at top
- **Search** across sessions when you have 4+
- **Click to expand** any session for path, PID, session ID details
- **Hover actions** — Focus terminal, Reveal in Finder, Copy path
- **Smart caching** — only re-parses JSONL files whose modification date changed
- **Notification debouncing** — re-notifies after 5 minutes, not every poll cycle

## Security

- AppleScript inputs validated against strict regex (TTY: `/dev/ttys[0-9]+`, session IDs: UUID format)
- Session file paths verified to stay within `~/.claude/projects/`
- PID ownership verified before dispatch (must be claude/node process)
- Clipboard cleared 1.5s after dispatch
- Wispr Flow key codes bounded to 0-127
- No data leaves your machine

See [SECURITY.md](SECURITY.md) for our vulnerability disclosure policy.

## Requirements

- macOS 14 (Sonoma) or later
- Claude Code CLI installed
- Accessibility permission (for terminal focus and dispatch)

## Development

```bash
make build      # Build universal binary
make install    # Install to /Applications
make clean      # Clean build artifacts
make release    # Create release zip with SHA-256
make sign       # Sign with Developer ID (requires IDENTITY=)
make notarize   # Notarize with Apple (requires APPLE_ID= TEAM_ID=)
```

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/your-feature`)
3. Commit your changes
4. Push to the branch and open a Pull Request

For bugs, please use the [bug report template](../../issues/new?template=bug_report.yml).

## Tool Support

Currently monitors **Claude Code** sessions. The architecture supports adding adapters for OpenCode, Gemini CLI, and other tools — contributions welcome.

## License

MIT

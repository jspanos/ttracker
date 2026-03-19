# TTracker

A lightweight, privacy-first macOS menu bar time tracker. Polls every 5 seconds for the active app and window title, stores everything in a local SQLite database, and generates a self-contained HTML report with charts.

![Build](https://github.com/jspanos/ttracker/actions/workflows/build.yml/badge.svg)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)
![License: MIT](https://img.shields.io/badge/License-MIT-green)

---

## Features

- **Menu bar app** — no Dock icon, stays out of your way
- **5-second polling** — precise session boundaries with no gaps or over-counting
- **Browser tab titles & URLs** — Chrome, Arc, Brave, Edge, Safari, Firefox
- **Terminal context** — current directory for Terminal and iTerm2
- **Idle detection** — configurable threshold; suppressed during audio/video playback
- **Meeting detection** — Zoom, FaceTime, Google Meet, and audio-active apps (Slack, Teams, Discord)
- **Input intensity** — keystroke, click, scroll, and mouse-distance tracking (optional)
- **Tracking day logic** — late-night sessions stay on the same day; a new day only starts after a gap + midnight crossing
- **tmux integration** — enriches terminal sessions with git branch, repo, and working directory
- **Self-contained HTML report** — daily breakdown, hourly timeline, input charts, top apps table
- **Universal binary** — runs natively on both Apple Silicon and Intel Macs

---

## Installation

### Download (recommended)

1. Download the latest `TTracker-vX.Y.Z.zip` from [Releases](https://github.com/jspanos/ttracker/releases)
2. Unzip and drag `TTracker.app` to `/Applications`
3. Right-click → **Open** on the first launch to bypass Gatekeeper (the app is ad-hoc signed, not notarized)
4. Grant the permissions below when prompted

### Build from source

Requirements: macOS 13+, Xcode Command Line Tools

```bash
xcode-select --install   # if not already installed

git clone https://github.com/jspanos/ttracker.git
cd ttracker/swift
./build.sh --install     # builds TTracker.app and copies to /Applications
```

To build a universal binary (arm64 + x86_64):

```bash
./build.sh --universal --install
```

---

## macOS Permissions

Grant these in **System Settings → Privacy & Security** when prompted on first launch:

| Permission | Required for |
|---|---|
| **Accessibility** | Window titles via AppleScript |
| **Automation** | Browser tab titles & URLs, terminal directories |
| **Input Monitoring** | Keystroke, click, and scroll counting |

Time tracking works without Input Monitoring — only input counts will be missing.

---

## What gets tracked

| App | What is recorded |
|---|---|
| Chrome / Arc / Brave / Edge | Active tab title and URL |
| Safari | Current tab title |
| Firefox | Front window name |
| Terminal / iTerm2 | Current working directory |
| All other apps | Front window title |

---

## Launch at Login

Open TTracker, click the menu bar icon → **Settings**, and toggle **Launch at Login**. This manages a LaunchAgent at `~/Library/LaunchAgents/com.ttracker.plist` automatically.

---

## Report

Click **View Report** in the menu bar. The report shows:

- Total tracked time and per-app breakdown for the selected day
- Hour-by-hour activity timeline with color-coded apps
- Input intensity chart (keystrokes + clicks per hour)
- Top apps and window titles table
- Navigation across the last 30 days

The report is saved to `~/.ttracker/report.html` and opened in a native WebKit window.

---

## Configuration

Click the menu bar icon → **Settings**:

| Setting | Default | Description |
|---|---|---|
| Idle threshold | 5 min | Inactivity before a session is closed |
| Suppress idle during audio | On | Keeps session open during video/music playback |
| Launch at Login | Off | Manages the LaunchAgent automatically |

---

## Data storage

All data is stored locally. Nothing is ever sent anywhere.

| Path | Contents |
|---|---|
| `~/.ttracker/data.db` | SQLite database (activities, snapshots, app_switches, tmux_events) |
| `~/.ttracker/report.html` | Last-generated report |
| `~/.ttracker/tracker.log` | App and LaunchAgent stdout/stderr |
| `~/.ttracker/time_audit.log` | Session open/close audit trail |

---

## tmux integration (optional)

Enriches terminal sessions with git branch, repo name, and working directory context.

Add to `~/.tmux.conf`:

```bash
bash /path/to/ttracker/tmux_telemetry.sh setup
```

This registers tmux hooks that send JSON to a Unix socket at `~/.ttracker/tmux.sock` whenever you switch panes or windows.

---

## Architecture

The app is a native macOS menu bar app written entirely in Swift (SPM, no external dependencies).

```
swift/Sources/ttracker/
  Tracker.swift            — session state machine; drives poll (5s) and snapshot (60s) timers
  AppMonitor.swift         — frontmost app detection + AppleScript enrichment
  InputMonitor.swift       — CGEvent tap for input counting
  Database.swift           — SQLite wrapper with automatic schema migrations
  TrackingDay.swift        — tracking day boundary logic
  ReportHTML.swift         — self-contained HTML report template
  StatusBarController.swift — NSStatusItem menu bar UI
  Settings.swift           — UserDefaults-backed preferences
  Constants.swift          — APP_CATEGORIES, MEETING_APPS, CALL_AUDIO_APPS, etc.
```

See [CLAUDE.md](CLAUDE.md) for a detailed architecture reference (session lifecycle, idle detection, meeting detection, database schema).

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## License

[MIT](LICENSE)

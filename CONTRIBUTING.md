# Contributing to TTracker

Thanks for your interest in contributing. TTracker is a native macOS app written entirely in Swift.

## Development setup

```bash
# Clone and build
git clone https://github.com/jspanos/ttracker.git
cd ttracker/swift
./build.sh

# Open the built app (required once for TCC permissions)
open build/TTracker.app
```

Grant **Accessibility**, **Automation**, and **Input Monitoring** in System Settings → Privacy & Security when prompted.

## Running during development

The app runs as a menu bar agent (`LSUIElement`). After making changes:

```bash
# Rebuild
cd swift && ./build.sh

# If running via LaunchAgent, restart it
launchctl stop com.ttracker  # KeepAlive restarts automatically

# Or just open the app directly
open swift/build/TTracker.app
```

Watch logs while it runs:

```bash
tail -f ~/.ttracker/tracker.log
tail -f ~/.ttracker/time_audit.log
```

## Project layout

```
swift/
  Sources/ttracker/
    Tracker.swift           — session state machine (core logic)
    AppMonitor.swift        — frontmost app + AppleScript enrichment
    InputMonitor.swift      — CGEvent tap for keystroke/click/scroll
    Database.swift          — SQLite wrapper + schema migrations
    TrackingDay.swift       — day boundary logic
    ReportHTML.swift        — HTML report template
    ReportGenerator.swift   — report data computation
    StatusBarController.swift — menu bar UI
    Settings.swift          — UserDefaults-backed preferences
    Constants.swift         — APP_CATEGORIES, MEETING_APPS, etc.
    ...
  build.sh        — build + bundle script
  Package.swift   — Swift Package Manager config
  Info.plist      — app bundle metadata
```

See [CLAUDE.md](CLAUDE.md) for a detailed architecture walkthrough.

## Guidelines

- **Correctness over features**: session timing accuracy and data integrity are the top priorities.
- **Privacy**: all data stays local. Don't add any network calls — not even for crash reporting.
- **No new dependencies**: the project intentionally has zero Swift package dependencies. Use system frameworks.
- **Schema changes**: add a migration in `Database.runMigrations()` — never break existing databases.
- **Test manually**: there are no automated tests. Test the specific scenario you changed (app switch timing, idle detection, sleep/wake, report rendering).

## Submitting changes

1. Fork the repo and create a branch from `main`.
2. Make your change with a focused commit message explaining *why*, not just what.
3. Open a pull request. Describe what the PR changes and how you verified it.

## Reporting bugs

Open a GitHub issue with:
- macOS version and chip (Intel / Apple Silicon)
- Steps to reproduce
- Relevant lines from `~/.ttracker/tracker.log` or `~/.ttracker/time_audit.log`

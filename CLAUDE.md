# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Running the tracker

```bash
# Build TTracker.app
cd swift && ./build.sh

# Install to /Applications
cd swift && ./build.sh --install

# Restart the running instance (LaunchAgent auto-restarts via KeepAlive)
launchctl stop com.ttracker

# View live logs
tail -f ~/.ttracker/tracker.log
tail -f ~/.ttracker/time_audit.log

# Open the report (from the menu bar or directly)
open ~/.ttracker/report.html
```

The LaunchAgent plist is at `~/Library/LaunchAgents/com.ttracker.plist` — managed by the app's Settings window (Launch at Login toggle). tmux hooks are configured in `~/.tmux.conf`.

## Architecture

All code is Swift, under `swift/Sources/ttracker/`. The app is a native macOS menu bar app (LSUIElement).

**Core files:**
- `Tracker.swift` — session state machine. Four concurrent execution contexts:
  - `Timer` at 5 s (`poll`) — gets frontmost app via `AppMonitor`, detects idle via HID idle seconds, writes closed sessions to SQLite
  - `Timer` at 60 s (`snapshot`) — writes a per-minute row to `snapshots` with input deltas and battery state
  - `InputMonitor` thread — CGEvent tap counting keystrokes, clicks, mouse distance, scroll events; delta consumed at session-close time
  - `TelemetryServer` thread — Unix socket at `~/.ttracker/tmux.sock` receiving JSON from `tmux_telemetry.sh`
- `AppMonitor.swift` — gets frontmost app, enriches with AppleScript (tab title, URL, terminal directory), detects meetings
- `InputMonitor.swift` — CGEvent tap for input counting
- `Database.swift` — SQLite wrapper (all reads/writes)
- `TrackingDay.swift` — tracking day boundary logic
- `SleepWakeMonitor.swift` — NSWorkspace sleep/wake notifications
- `TelemetryServer.swift` — tmux Unix socket server
- `ReportGenerator.swift` / `ReportHTML.swift` — HTML report generation, displayed in native WKWebView
- `StatusBarController.swift` — NSStatusItem menu bar UI
- `Settings.swift` / `SettingsWindowController.swift` — UserDefaults-backed settings with native UI
- `Constants.swift` — APP_CATEGORIES, MEETING_APPS, CALL_AUDIO_APPS, MODIFIER_KEYCODES, etc.

## Session lifecycle

`poll` drives the session state machine on `Tracker`:
- `startSession(activity, ts, fresh)` — snapshots input counters as baseline; if `fresh=true`, recomputes tracking day from DB
- `closeSession(endedAt)` — calls input counter delta and writes to `activities` via `db.saveSession()`
- `resetSession()` — clears session state (called after close or on idle entry)

**Timing precision:**
- App switch: session closes at `prevPoll` (last confirmed time), new session starts at same timestamp — no gap, no over-credit
- Idle: session closes at `now - idleSecs` (actual HID idle start), clamped to `>= sessStart + 1.0`
- Sleep: `handleSleep` stores `sleptAt`; `handleWake` closes any session that leaked through the sleep/wake timer race before resetting

## Database (`~/.ttracker/data.db`)

Four tables:
- `activities` — one row per uninterrupted session. Source of truth for all time calculations. `tracking_day` computed via `getTrackingDay()` at save time.
- `snapshots` — one row per minute with per-interval input deltas. Used for hourly intensity charts only.
- `app_switches` — one row per app/window change. Used only for switch-count charts, never for duration.
- `tmux_events` — one row per tmux hook fire. Metadata log, never used for duration.

`Database.runMigrations()` handles schema creation and column-level migrations (ALTER TABLE) so old databases are upgraded automatically.

## "Tracking day" logic

A new day starts only when **both**: gap since last activity > N hours (configurable, default 5h) AND the calendar date has changed. Late-night sessions stay on the same tracking day. Implemented in `TrackingDay.swift: getTrackingDay()`.

## Idle detection

```swift
let audioActive = isAudioActive()          // IOPMCopyAssertionsStatus
let threshold   = Settings.shared.idleThresholdSeconds   // configurable, default 5 min
let userIdle    = idleSecs >= threshold && !audioActive
```

- Audio playback (video, meeting) suppresses idle for all apps (configurable)
- `CALL_AUDIO_APPS` (Slack, Teams, Discord) — elevated to `is_meeting=true` when audio is active

## Meeting detection

`detectMeeting(appName, windowTitle, url)` in `AppMonitor.swift`:
1. `appName in MEETING_APPS` — always a meeting (Zoom, Webex, Skype, FaceTime, Around)
2. Keywords in combined windowTitle+url (meet.google.com, huddle, on a call, etc.)
3. In `poll`: audio active + app in `CALL_AUDIO_APPS` → `activity.isMeeting = true`

Note: `"Microsoft Teams"` is intentionally absent from `MEETING_APPS` — Teams is used for both chat and calls; audio detection handles the distinction.

## Input event counting

CGEvent tap in `InputMonitor.swift`:
- **Keystrokes**: filters modifier-only key codes (`MODIFIER_KEYCODES`) and auto-repeat events — counts only intentional character presses
- **Scrolls**: debounced at 150 ms — counts scroll gestures, not raw 60 Hz momentum ticks
- **Mouse distance**: accumulated Euclidean pixel distance (pixels, stored raw; report converts to meters)

## Key constants (`Constants.swift`)

- `IDLE_THRESHOLD_DEFAULT` — default idle threshold (configurable in Settings)
- `PASSIVE_APPS` — browsers/media; audio suppresses idle
- `CALL_AUDIO_APPS` — apps elevated to `is_meeting` when audio is active
- `MEETING_APPS` — apps that are always meetings
- `APP_CATEGORIES` — maps app display names to category strings
- `POLL_INTERVAL = 5`, `SNAPSHOT_INTERVAL = 60`

## tmux telemetry

`tmux_telemetry.sh` fires on tmux pane/window focus hooks, collects cwd (via `lsof`), running command, git branch/repo, and sends JSON to the Unix socket. The tracker only applies this to in-memory `telemetryState` when a terminal app is frontmost — otherwise logged to `tmux_events` only. Events that arrive while the app is down are queued in `~/.ttracker/tmux_queue.jsonl` and drained on next startup.

## Building

```bash
cd swift
./build.sh            # builds TTracker.app in swift/build/
./build.sh --install  # also copies to /Applications/TTracker.app
```

After rebuilding, restart the LaunchAgent:
```bash
launchctl stop com.ttracker   # KeepAlive restarts automatically
```

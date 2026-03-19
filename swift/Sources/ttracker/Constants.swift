// Constants.swift — All application-wide constants for TTracker
import Foundation

// MARK: - Paths

let DB_DIR            = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ttracker")
let DB_PATH           = DB_DIR.appendingPathComponent("data.db")
let AUDIT_LOG_PATH    = DB_DIR.appendingPathComponent("time_audit.log")
let SOCKET_PATH       = DB_DIR.appendingPathComponent("tmux.sock").path
let QUEUE_PATH        = DB_DIR.appendingPathComponent("tmux_queue.jsonl")
let REPORT_SCRIPT     = FileManager.default.homeDirectoryForCurrentUser
                            .appendingPathComponent("Project/ttracker/report.py").path

// MARK: - Timing

let POLL_INTERVAL:     TimeInterval = 5
let SNAPSHOT_INTERVAL: TimeInterval = 60
let SCROLL_DEBOUNCE:   TimeInterval = 0.15
let BATTERY_TTL:       TimeInterval = 120      // re-query battery at most every 2 min
// IDLE_THRESHOLD is now read from Settings.shared.idleThresholdSeconds

// MARK: - App sets

let BROWSER_APPS: Set<String> = [
    "Google Chrome", "Chrome", "Safari", "Firefox", "Arc",
    "Brave Browser", "Microsoft Edge", "Opera"
]

let TERMINAL_APPS: Set<String> = [
    "Terminal", "iTerm2", "iTerm", "Alacritty", "kitty", "Warp"
]

/// Apps that are always a meeting (Zoom, dedicated video-call apps).
/// Microsoft Teams is intentionally excluded: it's used for chat + calls;
/// audio detection handles the distinction.
let MEETING_APPS: Set<String> = [
    "Zoom", "Webex", "Skype", "FaceTime", "Around"
]

/// Passive apps (media/browsers). Previously had infinite idle; now they share
/// the same 5-minute threshold — only audio suppresses idle for all apps.
let PASSIVE_APPS: Set<String> = [
    "Google Chrome", "Safari", "Firefox", "Arc", "VLC",
    "QuickTime Player", "Spotify", "Music", "Podcasts",
    "IINA", "Infuse", "Plex", "Brave Browser"
]

/// Apps elevated to is_meeting=true when audio is active.
let CALL_AUDIO_APPS: Set<String> = ["Slack", "Microsoft Teams", "Discord"]

let MEETING_KEYWORDS: [String] = [
    "meet.google.com", "zoom.us/j", "zoom meeting",
    "microsoft teams meeting", "webex meeting", "google meet",
    "huddle", "on a call"
]

// MARK: - Categories

let APP_CATEGORIES: [String: String] = [
    // coding
    "Visual Studio Code": "coding", "Code": "coding", "Cursor": "coding",
    "Xcode": "coding", "PyCharm": "coding", "IntelliJ IDEA": "coding",
    "WebStorm": "coding", "GoLand": "coding", "RubyMine": "coding",
    "Sublime Text": "coding", "TextMate": "coding", "Nova": "coding",
    "BBEdit": "coding", "Zed": "coding", "Emacs": "coding", "MacVim": "coding",
    "Terminal": "coding", "iTerm2": "coding", "iTerm": "coding",
    "Warp": "coding", "Alacritty": "coding", "kitty": "coding",
    "GitHub Desktop": "coding", "Tower": "coding", "Sourcetree": "coding",
    "Sequel Pro": "coding", "TablePlus": "coding",
    "Postman": "coding", "Insomnia": "coding", "RapidAPI": "coding",
    "Simulator": "coding", "Instruments": "coding", "Dash": "coding",
    // communication
    "Slack": "communication", "Microsoft Teams": "communication",
    "Zoom": "communication", "Discord": "communication",
    "Messages": "communication", "Mail": "communication",
    "Outlook": "communication", "Spark": "communication",
    "Mimestream": "communication", "Telegram": "communication",
    "WhatsApp": "communication", "FaceTime": "communication",
    "Signal": "communication", "Skype": "communication",
    "Around": "communication", "Loom": "communication",
    // browser
    "Google Chrome": "browser", "Safari": "browser", "Firefox": "browser",
    "Arc": "browser", "Brave Browser": "browser",
    "Microsoft Edge": "browser", "Opera": "browser",
    // media
    "Spotify": "media", "Music": "media", "VLC": "media",
    "QuickTime Player": "media", "IINA": "media", "Podcasts": "media",
    "Infuse": "media", "Plex": "media", "Vinyls": "media",
    // productivity
    "Notion": "productivity", "Obsidian": "productivity",
    "Notes": "productivity", "Pages": "productivity",
    "Numbers": "productivity", "Keynote": "productivity",
    "Microsoft Word": "productivity", "Microsoft Excel": "productivity",
    "Microsoft PowerPoint": "productivity", "Figma": "productivity",
    "Sketch": "productivity", "Calendar": "productivity",
    "Reminders": "productivity", "Things 3": "productivity",
    "OmniFocus": "productivity", "Bear": "productivity",
    "Craft": "productivity", "Day One": "productivity",
    "Adobe Photoshop": "productivity", "Adobe Illustrator": "productivity",
    "Affinity Designer": "productivity", "Affinity Photo": "productivity",
    "Linear": "productivity", "Jira": "productivity",
    // system
    "Finder": "system", "System Preferences": "system",
    "System Settings": "system", "Activity Monitor": "system",
    "1Password": "system", "Bitwarden": "system",
    "Alfred": "system", "Raycast": "system",
    "CleanMyMac": "system", "iStat Menus": "system",
]

// MARK: - Modifier key codes (filtered from keystroke count)

/// Virtual key codes for modifier keys.  Pressed in isolation these are not
/// "keystrokes" and should not be counted toward productivity metrics.
let MODIFIER_KEYCODES: Set<Int64> = [
    54, 55,   // Cmd left, right
    56, 60,   // Shift left, right
    58, 61,   // Option left, right
    59, 62,   // Ctrl left, right
    63,       // Fn
    57,       // Caps Lock
]

// MARK: - Pixels → metres conversion

/// ~0.25 mm per logical pixel at typical display density.
let PX_TO_M: Double = 0.00025

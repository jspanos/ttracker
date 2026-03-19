// Models.swift — Core data types for TTracker
import Foundation

// MARK: - Activity

/// Represents the currently-focused application / window / tab snapshot.
struct Activity: Equatable {
    var appName:     String
    var bundleID:    String?
    var category:    String
    var windowTitle: String?
    var url:         String?
    var domain:      String?
    var tabCount:    Int?
    var isMeeting:   Bool

    static func unknown() -> Activity {
        Activity(appName: "Unknown", bundleID: nil, category: "other",
                 windowTitle: nil, url: nil, domain: nil, tabCount: nil, isMeeting: false)
    }
}

// MARK: - InputCounters

/// Cumulative input event counters since app launch.
struct InputCounters {
    var keystrokes:   Int    = 0
    var clicks:       Int    = 0
    var mouseDistPx:  Double = 0.0   // raw pixels
    var scrollEvents: Int    = 0

    /// Return per-field delta clamped to >= 0.
    func delta(from baseline: InputCounters) -> InputCounters {
        InputCounters(
            keystrokes:  max(0, keystrokes  - baseline.keystrokes),
            clicks:      max(0, clicks      - baseline.clicks),
            mouseDistPx: max(0, mouseDistPx - baseline.mouseDistPx),
            scrollEvents: max(0, scrollEvents - baseline.scrollEvents)
        )
    }
}

// MARK: - BatteryInfo

struct BatteryInfo {
    var percent:    Double?
    var isCharging: Bool?

    static let unknown = BatteryInfo(percent: nil, isCharging: nil)
}

// MARK: - TmuxState

/// In-memory state from the most recent telemetry payload.
/// Named "tmux" for historical compatibility but the socket accepts any JSON.
struct TelemetryState {
    var sessionName:  String?
    var windowIndex:  String?
    var windowName:   String?
    var paneIndex:    String?
    var paneTitle:    String?
    var paneDir:      String?
    var paneCmd:      String?
    var paneCount:    Int?
    var paneZoomed:   Bool     = false
    var windowCount:  Int?
    var sessionCount: Int?
    var gitBranch:    String?
    var gitRepo:      String?
    var timestamp:    Double   = 0

    /// Parse from a JSON dictionary (keys match tmux_telemetry.sh output).
    init(from dict: [String: Any]) {
        sessionName  = dict["session_name"]  as? String
        windowIndex  = dict["window_index"]  as? String
        windowName   = dict["window_name"]   as? String
        paneIndex    = dict["pane_index"]    as? String
        paneTitle    = dict["pane_title"]    as? String
        paneDir      = dict["pane_dir"]      as? String
        paneCmd      = dict["pane_cmd"]      as? String
        paneCount    = dict["pane_count"]    as? Int
        paneZoomed   = (dict["pane_zoomed"]  as? Bool) ?? false
        windowCount  = dict["window_count"]  as? Int
        sessionCount = dict["session_count"] as? Int
        gitBranch    = dict["git_branch"]    as? String
        gitRepo      = dict["git_repo"]      as? String
        timestamp    = (dict["timestamp"]    as? Double) ?? Date().timeIntervalSince1970
    }
}

// MARK: - WorkLimit

struct WorkLimit {
    var totalSeconds:  Double
    var startedAt:     Date
    var milestonesSent: Set<Int> = []
    var expired:       Bool      = false

    var elapsed: Double   { Date().timeIntervalSince(startedAt) }
    var remaining: Double { totalSeconds - elapsed }
    var pct: Double       { elapsed / totalSeconds }
}

// MARK: - Helpers

func formatDuration(_ seconds: Double) -> String {
    let s = Int(seconds)
    if s < 60  { return "\(s)s" }
    let m = s / 60
    if m < 60  { return "\(m)m" }
    return "\(m / 60)h \(m % 60)m"
}

/// Extract the domain from a URL string, stripping leading "www.".
func extractDomain(_ urlString: String?) -> String? {
    guard let urlString, !urlString.isEmpty,
          let url = URL(string: urlString),
          let host = url.host else { return nil }
    if host.hasPrefix("www.") {
        return String(host.dropFirst(4))
    }
    return host
}

/// Return true if the combined window title + URL contains a meeting keyword.
func detectMeeting(appName: String, windowTitle: String?, url: String?) -> Bool {
    if MEETING_APPS.contains(appName) { return true }
    let combined = "\(windowTitle ?? "") \(url ?? "")".lowercased()
    return MEETING_KEYWORDS.contains { combined.contains($0) }
}

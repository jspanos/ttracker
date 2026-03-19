// AppMonitor.swift — Frontmost-app detection + browser/terminal enrichment via osascript
import AppKit
import Foundation
import IOKit.pwr_mgt

// MARK: - AppleScript runner

/// Run an osascript one-liner. Returns stdout on success, nil on error.
/// Uses Process with explicit arguments — no shell injection possible.
func runAppleScript(_ script: String, timeout: TimeInterval = 3) -> String? {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    proc.arguments = ["-e", script]

    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError  = Pipe()  // discard stderr

    do {
        try proc.run()
    } catch {
        return nil
    }

    // Wait with a manual timeout via a background thread kill.
    let deadline = DispatchTime.now() + timeout
    let result = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        proc.waitUntilExit()
        result.signal()
    }
    if result.wait(timeout: deadline) == .timedOut {
        proc.terminate()
        return nil
    }

    guard proc.terminationStatus == 0 else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let str  = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    return str?.isEmpty == false ? str : nil
}

// MARK: - Frontmost app

/// Returns (localizedName, bundleIdentifier) of the frontmost application.
func getFrontmostApp() -> (name: String?, bundleID: String?) {
    let ws  = NSWorkspace.shared
    let app = ws.frontmostApplication
    return (app?.localizedName, app?.bundleIdentifier)
}

// MARK: - Browser enrichment

/// Returns (title, url, tabCount) for a Chromium-engine browser.
func chromiumInfo(appName: String) -> (title: String?, url: String?, tabCount: Int?) {
    let script = """
tell application "\(appName)"
    try
        set t to title of active tab of front window
        set u to URL   of active tab of front window
        set n to count of tabs of front window
        return t & "|||" & u & "|||" & n
    end try
end tell
"""
    guard let r = runAppleScript(script), r.contains("|||") else { return (nil, nil, nil) }
    let parts = r.components(separatedBy: "|||")
    let title = parts[0].isEmpty ? nil : parts[0]
    let url   = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
    let tabs  = parts.count > 2 ? Int(parts[2].trimmingCharacters(in: .whitespaces)) : nil
    return (title, url, tabs)
}

/// Returns (title, url, tabCount) for Safari.
func safariInfo() -> (title: String?, url: String?, tabCount: Int?) {
    let script = """
tell application "Safari"
    try
        set t to name of current tab of front window
        set u to URL  of current tab of front window
        set n to count of tabs of front window
        return t & "|||" & u & "|||" & n
    end try
end tell
"""
    guard let r = runAppleScript(script), r.contains("|||") else { return (nil, nil, nil) }
    let parts = r.components(separatedBy: "|||")
    let title = parts[0].isEmpty ? nil : parts[0]
    let url   = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
    let tabs  = parts.count > 2 ? Int(parts[2].trimmingCharacters(in: .whitespaces)) : nil
    return (title, url, tabs)
}

/// Returns (title, nil, nil) for Firefox (URL not available via AppleScript).
func firefoxInfo() -> (title: String?, url: String?, tabCount: Int?) {
    let title = runAppleScript(#"tell application "Firefox" to name of front window"#)
    return (title, nil, nil)
}

// MARK: - Terminal title parsing

/// Extract a meaningful directory or command string from a terminal window title.
/// Handles formats like "cmd — ~/path", "user@host: ~/path", "~/path", etc.
func parseTerminalTitle(_ title: String) -> String {
    if title.isEmpty { return title }
    // "cmd — ~/path" or "cmd – ~/path"
    let emDashPattern = try? NSRegularExpression(pattern: #"[—–]\s*(~?/[^\s].*)"#)
    let range = NSRange(title.startIndex..., in: title)
    if let m = emDashPattern?.firstMatch(in: title, range: range),
       let r = Range(m.range(at: 1), in: title) {
        return String(title[r]).trimmingCharacters(in: .whitespaces)
    }
    // "user@host: ~/path"
    let colonPattern = try? NSRegularExpression(pattern: #":\s*(~?/.+)$"#)
    if let m = colonPattern?.firstMatch(in: title, range: range),
       let r = Range(m.range(at: 1), in: title) {
        return String(title[r]).trimmingCharacters(in: .whitespaces)
    }
    if title.hasPrefix("~") || title.hasPrefix("/") {
        return title.trimmingCharacters(in: .whitespaces)
    }
    return title
}

func terminalTitle() -> String? {
    let r = runAppleScript(#"tell application "Terminal" to title of front window"#)
    return r.map { parseTerminalTitle($0) }
}

func iterm2Title(telemetryState: TelemetryState?) -> String? {
    // Prefer rich telemetry if it arrived within 30 s.
    if let state = telemetryState,
       Date().timeIntervalSince1970 - state.timestamp < 30 {
        var parts: [String] = []
        if let repo = state.gitRepo {
            var s = repo
            if let branch = state.gitBranch { s += ":\(branch)" }
            parts.append(s)
        }
        if let dir = state.paneDir {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let d    = dir.hasPrefix(home) ? "~" + dir.dropFirst(home.count) : dir
            parts.append(d)
        }
        let shellCommands: Set<String> = ["zsh", "bash", "fish"]
        if let cmd = state.paneCmd, !shellCommands.contains(cmd) {
            parts.append("[\(cmd)]")
        }
        if let session = state.sessionName {
            parts.append("tmux:\(session)")
        }
        if !parts.isEmpty { return parts.joined(separator: " · ") }
        return state.paneTitle
    }

    // Fallback: AppleScript
    let script = """
tell application "iTerm2"
    try
        set sess to current session of current tab of current window
        return name of sess
    on error
        try
            return name of current tab of current window
        end try
    end try
end tell
"""
    guard let r = runAppleScript(script) else { return nil }
    // Strip leading "[tag] " prefix common in iTerm2 titles.
    let stripped = r.replacingOccurrences(of: #"^\[[^\]]*\]\s*"#,
                                          with: "",
                                          options: .regularExpression)
    return parseTerminalTitle(stripped.isEmpty ? r : stripped)
}

func genericTitle(appName: String) -> String? {
    runAppleScript("""
tell application "System Events"
    tell process "\(appName)"
        try
            return name of front window
        end try
    end tell
end tell
""")
}

// MARK: - Activity assembly

/// Get the full Activity for the currently frontmost application.
func getCurrentActivity(telemetryState: TelemetryState?) -> Activity {
    let (appName, bundleID) = getFrontmostApp()
    guard let appName else { return Activity.unknown() }

    let category = APP_CATEGORIES[appName] ?? "other"
    var windowTitle: String? = nil
    var url:         String? = nil
    var tabCount:    Int?    = nil

    do {
        switch appName {
        case "Google Chrome", "Chrome":
            (windowTitle, url, tabCount) = chromiumInfo(appName: "Google Chrome")
        case "Arc":
            (windowTitle, url, tabCount) = chromiumInfo(appName: "Arc")
        case "Brave Browser":
            (windowTitle, url, tabCount) = chromiumInfo(appName: "Brave Browser")
        case "Microsoft Edge":
            (windowTitle, url, tabCount) = chromiumInfo(appName: "Microsoft Edge")
        case "Opera":
            (windowTitle, url, tabCount) = chromiumInfo(appName: "Opera")
        case "Safari":
            (windowTitle, url, tabCount) = safariInfo()
        case "Firefox":
            (windowTitle, url, tabCount) = firefoxInfo()
        case "Terminal":
            windowTitle = terminalTitle()
        case "iTerm2", "iTerm":
            windowTitle = iterm2Title(telemetryState: telemetryState)
        default:
            windowTitle = genericTitle(appName: appName)
        }
    }

    let domain    = extractDomain(url)
    let isMeeting = detectMeeting(appName: appName, windowTitle: windowTitle, url: url)

    return Activity(
        appName:     appName,
        bundleID:    bundleID,
        category:    category,
        windowTitle: windowTitle?.isEmpty == false ? windowTitle : nil,
        url:         url,
        domain:      domain,
        tabCount:    tabCount,
        isMeeting:   isMeeting
    )
}

// MARK: - Battery info

/// Query battery percentage and charging state via pmset.
func getBatteryInfo() -> BatteryInfo {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    proc.arguments = ["-g", "batt"]
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError  = Pipe()
    guard (try? proc.run()) != nil else { return .unknown }
    proc.waitUntilExit()
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let pctMatch = try? NSRegularExpression(pattern: #"(\d+)%;"#)
    var percent: Double? = nil
    let nsRange = NSRange(output.startIndex..., in: output)
    if let m = pctMatch?.firstMatch(in: output, range: nsRange),
       let r = Range(m.range(at: 1), in: output) {
        percent = Double(output[r])
    }
    let isCharging = output.lowercased().contains("charging") || output.contains("AC Power")
    return BatteryInfo(percent: percent, isCharging: isCharging)
}

// MARK: - Audio / media detection

/// Return true if any app is actively playing media (video or audio).
///
/// Uses IOKit `IOPMCopyAssertionsStatus` — browsers and media players post
/// `NoDisplaySleepAssertion` ("Video Wake Lock") and `NoIdleSleepAssertion`
/// ("Playing audio") while content is playing. This is a native in-process call:
/// no subprocess, no blocking, works on all Mac hardware including Apple Silicon.
///
/// The previous ioreg/IOAudioEngine approach returned no output on this machine
/// because Apple Silicon uses different audio driver names.
func isAudioPlaying() -> Bool {
    var ref: Unmanaged<CFDictionary>? = nil
    guard IOPMCopyAssertionsStatus(&ref) == kIOReturnSuccess,
          let dict = ref?.takeRetainedValue() as? [String: NSNumber]
    else { return false }

    // Browsers post these when playing video or audio.
    let mediaKeys = ["NoDisplaySleepAssertion", "NoIdleSleepAssertion",
                     "PreventUserIdleDisplaySleep"]
    return mediaKeys.contains { dict[$0]?.intValue ?? 0 > 0 }
}

// MARK: - Notification

func sendNotification(title: String, message: String) {
    let script = "display notification \"\(message.replacingOccurrences(of: "\"", with: "\\\""))\" with title \"\(title.replacingOccurrences(of: "\"", with: "\\\""))\""
    _ = runAppleScript(script)
}

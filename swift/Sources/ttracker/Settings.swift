// Settings.swift — Persistent user preferences backed by UserDefaults
// Launch-at-login and auto-restart are managed via the LaunchAgent plist so
// that KeepAlive (crash-restart) is supported — SMAppService doesn't offer that.
import Foundation

final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard
    private init() {}

    // MARK: - Idle Detection

    var idleThresholdMinutes: Int {
        get {
            let v = defaults.integer(forKey: "idleThresholdMinutes")
            return v > 0 ? v : 5
        }
        set { defaults.set(max(1, newValue), forKey: "idleThresholdMinutes") }
    }

    var idleThresholdSeconds: TimeInterval {
        TimeInterval(idleThresholdMinutes) * 60
    }

    var audioSuppressesIdle: Bool {
        get { defaults.object(forKey: "audioSuppressesIdle") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "audioSuppressesIdle") }
    }

    // MARK: - Tracking Day

    var trackingDayGapHours: Double {
        get {
            let v = defaults.double(forKey: "trackingDayGapHours")
            return v > 0 ? v : 5.0
        }
        set { defaults.set(max(1.0, newValue), forKey: "trackingDayGapHours") }
    }

    // MARK: - Notifications

    var notificationsEnabled: Bool {
        get { defaults.object(forKey: "notificationsEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notificationsEnabled") }
    }

    var notificationIntervalMinutes: Int {
        get {
            let v = defaults.integer(forKey: "notificationIntervalMinutes")
            return v > 0 ? v : 30
        }
        set { defaults.set(max(5, newValue), forKey: "notificationIntervalMinutes") }
    }

    var milestoneSoundsEnabled: Bool {
        get { defaults.object(forKey: "milestoneSoundsEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "milestoneSoundsEnabled") }
    }

    // MARK: - Launch at Login

    /// Whether the LaunchAgent plist is currently loaded (i.e. runs at login).
    var launchAtLogin: Bool {
        get { isAgentLoaded() }
        set {
            if newValue {
                writeAgentPlist(keepAlive: autoRestart)
                loadAgent()
            } else {
                unloadAgent()
            }
        }
    }

    // MARK: - Auto-restart on crash

    /// When enabled, KeepAlive=true is written to the LaunchAgent plist so
    /// launchd restarts TTracker automatically after a crash or exit.
    var autoRestart: Bool {
        get { defaults.object(forKey: "autoRestart") as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: "autoRestart")
            // Re-write and reload the plist if it's already installed.
            if isAgentLoaded() {
                writeAgentPlist(keepAlive: newValue)
                reloadAgent()
            } else if FileManager.default.fileExists(atPath: agentPlistURL.path) {
                writeAgentPlist(keepAlive: newValue)
            }
        }
    }

    // MARK: - LaunchAgent helpers

    private let agentLabel   = "com.ttracker"
    private let agentPlistURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/com.ttracker.plist")

    private var homeDir: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    /// The binary to put in ProgramArguments — always this app's own executable.
    private var binaryPath: String {
        Bundle.main.executablePath
            ?? "\(homeDir)/Project/ttracker/swift/build/TTracker.app/Contents/MacOS/ttracker"
    }

    func isAgentLoaded() -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments     = ["list", agentLabel]
        proc.standardOutput = Pipe()
        proc.standardError  = Pipe()
        try? proc.run()
        proc.waitUntilExit()
        return proc.terminationStatus == 0
    }

    /// Writes (or overwrites) the plist at ~/Library/LaunchAgents/com.ttracker.plist.
    func writeAgentPlist(keepAlive: Bool) {
        let logPath = "\(homeDir)/.ttracker/tracker.log"
        let xml = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>\(agentLabel)</string>
    <key>ProgramArguments</key>
    <array>
        <string>\(binaryPath)</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <\(keepAlive ? "true" : "false")/>
    <key>StandardOutPath</key>
    <string>\(logPath)</string>
    <key>StandardErrorPath</key>
    <string>\(logPath)</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>\(homeDir)</string>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>
"""
        try? xml.write(to: agentPlistURL, atomically: true, encoding: .utf8)
    }

    private func uid() -> UInt32 { getuid() }

    private func launchctl(_ args: [String]) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments     = args
        proc.standardOutput = Pipe()
        proc.standardError  = Pipe()
        try? proc.run()
        proc.waitUntilExit()
    }

    private func loadAgent() {
        launchctl(["bootstrap", "gui/\(uid())", agentPlistURL.path])
    }

    private func unloadAgent() {
        launchctl(["bootout", "gui/\(uid())", agentPlistURL.path])
    }

    private func reloadAgent() {
        unloadAgent()
        loadAgent()
    }
}

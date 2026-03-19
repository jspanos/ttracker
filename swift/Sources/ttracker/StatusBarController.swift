// StatusBarController.swift — NSStatusItem menu bar UI
import AppKit
import Foundation

final class StatusBarController {

    // MARK: Properties

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    // Menu items
    private var currentItem: NSMenuItem!
    private var todayItem:   NSMenuItem!
    private var pauseItem:   NSMenuItem!

    private weak var tracker: Tracker?

    // MARK: Init

    init(tracker: Tracker) {
        self.tracker = tracker

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildMenu()

        if let button = statusItem.button {
            button.title = "⏱"
        }
    }

    // MARK: Menu construction

    private func buildMenu() {
        menu = NSMenu()

        currentItem = NSMenuItem(title: "● —", action: nil, keyEquivalent: "")
        currentItem.isEnabled = false
        menu.addItem(currentItem)

        todayItem = NSMenuItem(title: "Today: 0h 0m", action: nil, keyEquivalent: "")
        todayItem.isEnabled = false
        menu.addItem(todayItem)

        menu.addItem(.separator())

        let reportItem = NSMenuItem(title: "View Report", action: #selector(openReport), keyEquivalent: "")
        reportItem.target = self
        menu.addItem(reportItem)

        pauseItem = NSMenuItem(title: "Pause / Resume", action: #selector(togglePause), keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let limitItem = NSMenuItem(title: "Set Work Limit…", action: #selector(setLimit), keyEquivalent: "")
        limitItem.target = self
        menu.addItem(limitItem)

        let clearItem = NSMenuItem(title: "Clear Limit", action: #selector(clearLimit), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Update from Tracker

    /// Called after every poll / countdown tick.
    func update(activity: Activity?, totalSecs: Double, isIdle: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateCurrentItem(activity: activity, isIdle: isIdle)
            self.updateTodayItem(totalSecs: totalSecs)
            self.updateTitle(activity: activity, totalSecs: totalSecs, isIdle: isIdle)
        }
    }

    private func updateCurrentItem(activity: Activity?, isIdle: Bool) {
        guard let tracker else { return }
        if tracker.isPaused {
            currentItem.title = "● Paused"
            return
        }
        if isIdle || activity == nil {
            currentItem.title = "● Idle"
            return
        }
        var label = "● \(activity!.appName)"
        if let title = activity?.windowTitle {
            let truncated = title.count > 35 ? String(title.prefix(35)) + "…" : title
            label += " — \(truncated)"
        }
        if activity?.isMeeting == true {
            label = "📹 " + label
        }
        currentItem.title = label
    }

    private func updateTodayItem(totalSecs: Double) {
        let total = Int(totalSecs)
        let h     = total / 3600
        let m     = (total % 3600) / 60
        todayItem.title = "Today: \(h)h \(m)m"
    }

    private func updateTitle(activity: Activity?, totalSecs: Double, isIdle: Bool) {
        guard let tracker else { return }

        if tracker.isPaused {
            setPlainTitle("⏹ Paused")
            return
        }

        if isIdle {
            setPlainTitle("⏸ Idle")
            return
        }

        let (limitSnap, blinkOn) = tracker.workLimitSnapshot()

        if let limit = limitSnap {
            drawLimitTitle(limit: limit, blinkOn: blinkOn)
            return
        }

        // Normal: show elapsed time
        let total = Int(totalSecs)
        let h     = total / 3600
        let m     = (total % 3600) / 60
        setPlainTitle("⏱ \(h)h \(m)m")
    }

    // MARK: - Title helpers

    private func setPlainTitle(_ text: String) {
        statusItem.button?.attributedTitle = NSAttributedString(string: "")
        statusItem.button?.title           = text
    }

    private func setColoredTitle(_ text: String, r: CGFloat, g: CGFloat, b: CGFloat) {
        let color = NSColor(calibratedRed: r, green: g, blue: b, alpha: 1.0)
        let font  = NSFont.menuBarFont(ofSize: 0)
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font:            font,
        ]
        statusItem.button?.attributedTitle = NSAttributedString(string: text, attributes: attrs)
    }

    private func drawLimitTitle(limit: WorkLimit, blinkOn: Bool) {
        let remaining = limit.remaining
        let pct       = limit.pct

        if remaining > 0 {
            let m    = Int(remaining) / 60
            let s    = Int(remaining) % 60
            let text = String(format: "⏱ %d:%02d", m, s)
            if pct >= 0.8 {
                // Gradient orange → red as pct goes 0.8 → 1.0
                let t     = min((pct - 0.8) / 0.2, 1.0)
                let green = 0.55 * (1.0 - t) + 0.2 * t
                let blue  = 0.0  * (1.0 - t) + 0.2 * t
                setColoredTitle(text, r: 1.0, g: green, b: blue)
            } else {
                setColoredTitle(text, r: 0.89, g: 0.91, b: 0.94)
            }
        } else {
            let over = Int(-remaining)
            let m    = over / 60
            let s    = over % 60
            let text = String(format: "⏱ -%d:%02d", m, s)
            if blinkOn {
                setColoredTitle(text, r: 1.0,  g: 0.2,  b: 0.2)   // bright red
            } else {
                setColoredTitle(text, r: 0.45, g: 0.08, b: 0.08)   // dim red
            }
        }
    }

    // MARK: - Menu actions

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func openReport() {
        if let t = tracker {
            ReportWindowController.show(db: t.db)
        }
    }

    @objc private func togglePause() {
        tracker?.togglePause()
        let paused = tracker?.isPaused ?? false
        setPlainTitle(paused ? "⏹ Paused" : "⏱")
    }

    @objc private func setLimit() {
        // Use a small dialog to ask for minutes.
        let alert = NSAlert()
        alert.messageText     = "Set Work Limit"
        alert.informativeText = "Enter work limit in minutes (e.g. 60):"
        alert.addButton(withTitle: "Set")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.placeholderString = "60"
        input.stringValue       = "60"
        alert.accessoryView     = input

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            guard let mins = Int(input.stringValue.trimmingCharacters(in: .whitespaces)),
                  mins > 0 else {
                showAlert(title: "Invalid Input",
                          message: "Enter a whole number of minutes.")
                return
            }
            tracker?.setWorkLimit(minutes: mins)
        }
    }

    @objc private func clearLimit() {
        tracker?.clearWorkLimit()
        setPlainTitle("⏱")
    }

    @objc private func quitApp() {
        tracker?.quit()
        NSApp.terminate(nil)
    }

    // MARK: Helpers

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText     = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

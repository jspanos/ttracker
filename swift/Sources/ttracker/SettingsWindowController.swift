// SettingsWindowController.swift — Native AppKit settings panel
import AppKit

final class SettingsWindowController: NSWindowController {

    static let shared = SettingsWindowController()

    // MARK: Controls (set in buildUI, used in loadSettings / actions)

    private var launchAtLoginBtn:   NSButton!
    private var autoRestartBtn:     NSButton!
    private var idlePopup:          NSPopUpButton!
    private var audioSuppressBtn:   NSButton!
    private var gapPopup:           NSPopUpButton!
    private var notificationsBtn:   NSButton!
    private var notifIntervalPopup: NSPopUpButton!
    private var soundsBtn:          NSButton!

    // MARK: Init

    private init() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 100),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "TTracker Settings"
        w.isReleasedWhenClosed = false
        super.init(window: w)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Show

    func show() {
        loadSettings()
        if !(window?.isVisible ?? false) { window?.center() }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - UI Construction

    private func buildUI() {
        let s = Settings.shared

        launchAtLoginBtn = checkbox("Launch TTracker at login",
                                    #selector(toggleLaunchAtLogin))

        autoRestartBtn = checkbox("Auto-restart if TTracker crashes or exits",
                                   #selector(toggleAutoRestart))

        idlePopup = makePopup(
            items:       [("2 min", 2), ("3 min", 3), ("5 min", 5),
                          ("10 min", 10), ("15 min", 15), ("30 min", 30)],
            selectedTag: s.idleThresholdMinutes,
            action:      #selector(idleChanged)
        )

        audioSuppressBtn = checkbox("Suppress idle while audio is playing",
                                     #selector(toggleAudioSuppress))

        gapPopup = makePopup(
            items:       [("3 h", 3), ("4 h", 4), ("5 h", 5),
                          ("6 h", 6), ("8 h", 8), ("12 h", 12)],
            selectedTag: Int(s.trackingDayGapHours),
            action:      #selector(gapChanged)
        )

        notificationsBtn = checkbox("Hourly summary notifications",
                                     #selector(toggleNotifications))

        notifIntervalPopup = makePopup(
            items:       [("15 min", 15), ("30 min", 30), ("60 min", 60)],
            selectedTag: s.notificationIntervalMinutes,
            action:      #selector(notifIntervalChanged)
        )

        soundsBtn = checkbox("Play sounds at work-limit milestones",
                              #selector(toggleSounds))

        let sections: [NSView] = [
            section("General", rows: [
                row("",               launchAtLoginBtn),
                row("",               autoRestartBtn),
            ]),
            section("Idle Detection", rows: [
                row("Mark idle after:", idlePopup),
                row("",                audioSuppressBtn),
            ]),
            section("Tracking Day", rows: [
                row("New day after:", hstack([gapPopup, note("inactivity gap + calendar date change")])),
            ]),
            section("Notifications", rows: [
                row("",         notificationsBtn),
                row("Interval:", notifIntervalPopup),
                row("",         soundsBtn),
            ]),
        ]

        let mainStack = NSStackView(views: sections)
        mainStack.orientation = .vertical
        mainStack.spacing     = 12
        mainStack.edgeInsets  = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        mainStack.alignment   = .width

        window?.contentView = mainStack
        mainStack.layoutSubtreeIfNeeded()
        let fit = mainStack.fittingSize
        window?.setContentSize(NSSize(width: max(fit.width, 440), height: fit.height))
    }

    private func loadSettings() {
        let s = Settings.shared
        launchAtLoginBtn.state   = s.launchAtLogin               ? .on : .off
        autoRestartBtn.state     = s.autoRestart                 ? .on : .off
        idlePopup.selectItem(withTag: s.idleThresholdMinutes)
        audioSuppressBtn.state   = s.audioSuppressesIdle         ? .on : .off
        gapPopup.selectItem(withTag: Int(s.trackingDayGapHours))
        notificationsBtn.state   = s.notificationsEnabled        ? .on : .off
        notifIntervalPopup.selectItem(withTag: s.notificationIntervalMinutes)
        soundsBtn.state          = s.milestoneSoundsEnabled      ? .on : .off
    }

    // MARK: - Actions

    @objc private func toggleLaunchAtLogin() {
        Settings.shared.launchAtLogin = (launchAtLoginBtn.state == .on)
        // Re-read actual state in case load/unload failed
        launchAtLoginBtn.state = Settings.shared.launchAtLogin ? .on : .off
    }

    @objc private func toggleAutoRestart() {
        Settings.shared.autoRestart = (autoRestartBtn.state == .on)
    }

    @objc private func idleChanged() {
        guard let tag = idlePopup.selectedItem?.tag else { return }
        Settings.shared.idleThresholdMinutes = tag
    }

    @objc private func toggleAudioSuppress() {
        Settings.shared.audioSuppressesIdle = (audioSuppressBtn.state == .on)
    }

    @objc private func gapChanged() {
        guard let tag = gapPopup.selectedItem?.tag else { return }
        Settings.shared.trackingDayGapHours = Double(tag)
    }

    @objc private func toggleNotifications() {
        Settings.shared.notificationsEnabled = (notificationsBtn.state == .on)
    }

    @objc private func notifIntervalChanged() {
        guard let tag = notifIntervalPopup.selectedItem?.tag else { return }
        Settings.shared.notificationIntervalMinutes = tag
    }

    @objc private func toggleSounds() {
        Settings.shared.milestoneSoundsEnabled = (soundsBtn.state == .on)
    }

    // MARK: - Layout helpers

    private static let labelWidth: CGFloat = 160

    private func checkbox(_ title: String, _ action: Selector) -> NSButton {
        NSButton(checkboxWithTitle: title, target: self, action: action)
    }

    private func makePopup(items: [(String, Int)], selectedTag: Int, action: Selector) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        for (title, tag) in items {
            popup.addItem(withTitle: title)
            popup.lastItem!.tag = tag
        }
        popup.selectItem(withTag: selectedTag)
        popup.target = self
        popup.action = action
        return popup
    }

    private func lbl(_ text: String) -> NSTextField {
        let tf = NSTextField(labelWithString: text)
        tf.alignment = .right
        tf.widthAnchor.constraint(equalToConstant: SettingsWindowController.labelWidth).isActive = true
        return tf
    }

    private func note(_ text: String) -> NSTextField {
        let tf = NSTextField(labelWithString: text)
        tf.font      = .systemFont(ofSize: NSFont.smallSystemFontSize)
        tf.textColor = .secondaryLabelColor
        return tf
    }

    private func hstack(_ views: [NSView]) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal
        s.spacing     = 6
        s.alignment   = .centerY
        return s
    }

    /// One labeled row: a right-aligned label (or empty spacer) + control.
    private func row(_ labelText: String, _ control: NSView) -> NSStackView {
        let s = NSStackView(views: [lbl(labelText), control])
        s.orientation = .horizontal
        s.spacing     = 8
        s.alignment   = .centerY
        return s
    }

    /// A titled NSBox group containing a vertical stack of rows.
    private func section(_ title: String, rows: [NSView]) -> NSBox {
        let box   = NSBox()
        box.title = title

        let inner = NSStackView(views: rows)
        inner.orientation = .vertical
        inner.spacing     = 10
        inner.edgeInsets  = NSEdgeInsets(top: 4, left: 12, bottom: 10, right: 12)
        inner.alignment   = .leading
        inner.translatesAutoresizingMaskIntoConstraints = false

        box.contentView!.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: box.contentView!.topAnchor),
            inner.leadingAnchor.constraint(equalTo: box.contentView!.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: box.contentView!.trailingAnchor),
            inner.bottomAnchor.constraint(equalTo: box.contentView!.bottomAnchor),
        ])

        return box
    }
}

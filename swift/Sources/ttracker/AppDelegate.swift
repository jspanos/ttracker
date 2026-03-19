// AppDelegate.swift — NSApplicationDelegate: wires together all components
import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var tracker:    Tracker!
    private var statusBar:  StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide Dock icon and Cmd-Tab — menu bar only app (LSUIElement=YES handles
        // this at launch, but this ensures it sticks even if the plist is missing).
        NSApp.setActivationPolicy(.accessory)

        // Ensure ~/.ttracker directory exists.
        try? FileManager.default.createDirectory(at: DB_DIR,
                                                  withIntermediateDirectories: true)

        tracker   = Tracker()
        statusBar = StatusBarController(tracker: tracker)

        // Wire refresh callback.
        tracker.onRefresh = { [weak self] activity, totalSecs, isIdle in
            self?.statusBar.update(activity: activity,
                                   totalSecs: totalSecs,
                                   isIdle: isIdle)
        }

        tracker.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        tracker?.quit()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Never quit when windows are closed — this is a menu-bar-only app.
        return false
    }
}

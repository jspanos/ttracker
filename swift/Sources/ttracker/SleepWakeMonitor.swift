// SleepWakeMonitor.swift — NSWorkspace sleep/wake notification observer
import AppKit
import Foundation

final class SleepWakeMonitor {

    var onSleep: (() -> Void)?
    var onWake:  (() -> Void)?

    private var tokens: [NSObjectProtocol] = []

    func start() {
        let nc = NSWorkspace.shared.notificationCenter

        let sleepToken = nc.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object:  nil,
            queue:   .main
        ) { [weak self] _ in
            self?.onSleep?()
        }

        let wakeToken = nc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object:  nil,
            queue:   .main
        ) { [weak self] _ in
            self?.onWake?()
        }

        tokens = [sleepToken, wakeToken]
    }

    deinit {
        let nc = NSWorkspace.shared.notificationCenter
        tokens.forEach { nc.removeObserver($0) }
    }
}

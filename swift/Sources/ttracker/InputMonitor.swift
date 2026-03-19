// InputMonitor.swift — CGEvent tap for keystroke / click / mouse / scroll counting
// Requires "Input Monitoring" permission (Privacy & Security → Input Monitoring)
// for keyboard events. Mouse/scroll events work without it.
import CoreGraphics
import Foundation

final class InputMonitor {

    // MARK: State (protected by lock)

    private let lock = NSLock()
    private var counters   = InputCounters()
    private var lastPos:   CGPoint?
    private var lastScrollTS: TimeInterval = 0

    // MARK: Start

    func start() {
        // Run the event tap on a dedicated background thread that owns its own
        // CFRunLoop so it never blocks the main thread.
        Thread.detachNewThread {
            self.runTap()
        }
    }

    // MARK: Public counter access

    /// Snapshot the current cumulative counters.
    func getCounters() -> InputCounters {
        lock.lock()
        defer { lock.unlock() }
        return counters
    }

    // MARK: Event handling — called from the CGEvent tap callback

    func handle(type: CGEventType, event: CGEvent) {
        lock.lock()
        defer { lock.unlock() }

        switch type {
        case .keyDown:
            let keycode    = event.getIntegerValueField(.keyboardEventKeycode)
            let autorepeat = event.getIntegerValueField(.keyboardEventAutorepeat)
            if autorepeat == 0 && !MODIFIER_KEYCODES.contains(keycode) {
                counters.keystrokes += 1
            }

        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            counters.clicks += 1

        case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
            let loc = event.location
            if let prev = lastPos {
                let dx = loc.x - prev.x
                let dy = loc.y - prev.y
                counters.mouseDistPx += sqrt(dx * dx + dy * dy)
            }
            lastPos = loc

        case .scrollWheel:
            let now = Date().timeIntervalSinceReferenceDate
            if now - lastScrollTS >= SCROLL_DEBOUNCE {
                counters.scrollEvents += 1
                lastScrollTS = now
            }

        default:
            break
        }
    }

    // MARK: Private — CGEvent tap setup

    private func runTap() {
        var mask: CGEventMask = 0
        mask |= CGEventMask(1 << CGEventType.keyDown.rawValue)
        mask |= CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
        mask |= CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
        mask |= CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
        mask |= CGEventMask(1 << CGEventType.mouseMoved.rawValue)
        mask |= CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
        mask |= CGEventMask(1 << CGEventType.rightMouseDragged.rawValue)
        mask |= CGEventMask(1 << CGEventType.scrollWheel.rawValue)

        // Retain self in the refcon pointer for the C callback.
        let refcon = Unmanaged.passRetained(self).toOpaque()

        let callback: CGEventTapCallBack = { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
            guard let refcon else { return nil }
            Unmanaged<InputMonitor>.fromOpaque(refcon).takeUnretainedValue()
                .handle(type: type, event: event)
            return nil
        }

        guard let tap = CGEvent.tapCreate(
            tap:        .cgSessionEventTap,
            place:      .headInsertEventTap,
            options:    .listenOnly,
            eventsOfInterest: mask,
            callback:   callback,
            userInfo:   refcon
        ) else {
            print("[ttracker] CGEvent tap unavailable — enable Accessibility in Privacy & Security")
            // Release the retained self since the tap was never created.
            Unmanaged<InputMonitor>.fromOpaque(refcon).release()
            return
        }

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        let rl     = CFRunLoopGetCurrent()
        CFRunLoopAddSource(rl, source, .defaultMode)
        CGEvent.tapEnable(tap: tap, enable: true)
        CFRunLoopRun()
    }
}

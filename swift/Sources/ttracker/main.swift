// main.swift — Entry point for TTracker (Swift Package Manager executable)
// Top-level code in main.swift is the SPM executable entry point.
import AppKit
import Darwin

// ── Single-instance lock ──────────────────────────────────────────────────────
// Acquire an exclusive BSD file lock on ~/.ttracker/ttracker.lock.
// flock() is released automatically when the process exits (even on crash),
// so there are no stale lock files.
let lockPath = NSHomeDirectory() + "/.ttracker/ttracker.lock"
try? FileManager.default.createDirectory(atPath: NSHomeDirectory() + "/.ttracker",
                                         withIntermediateDirectories: true)
let lockFD = open(lockPath, O_CREAT | O_WRONLY, 0o644)
guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
    fputs("[ttracker] Another instance is already running. Exiting.\n", stderr)
    exit(1)
}
// Write our PID into the lock file for diagnostics.
let pid = "\(ProcessInfo.processInfo.processIdentifier)\n"
_ = pid.withCString { write(lockFD, $0, strlen($0)) }
// ─────────────────────────────────────────────────────────────────────────────

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()

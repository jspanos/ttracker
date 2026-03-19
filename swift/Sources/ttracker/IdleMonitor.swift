// IdleMonitor.swift — HID idle detection via CGEventSource
import CoreGraphics
import Foundation

/// Returns seconds since the last keyboard, mouse, or trackpad event
/// using the HID (Human Interface Device) state.
/// kCGAnyInputEventType matches all input event types.
func getIdleSeconds() -> TimeInterval {
    // kCGAnyInputEventType = CGEventType(rawValue: ~UInt32(0))
    let anyEvent = CGEventType(rawValue: ~UInt32(0))!
    return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyEvent)
}

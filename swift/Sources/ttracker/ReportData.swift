// ReportData.swift
import Foundation

struct DaySummary {
    var totalActiveSecs: Double = 0
    var sessionCount:    Int    = 0
    var meetingCount:    Int    = 0
    var keystrokes:      Int    = 0
    var clicks:          Int    = 0
    var mouseDistMeters: Double = 0
    var scrollEvents:    Int    = 0
}

struct AppUsageRow: Identifiable {
    let id       = UUID()
    let appName:  String
    let category: String
    let duration: Double
    let sessions: Int
}

struct CategoryRow: Identifiable {
    let id       = UUID()
    let category: String
    let duration: Double
    let sessions: Int
}

struct HourlyBucket: Identifiable {
    let id:         Int
    let hour:       Int
    let activeSecs: Double
    let keystrokes: Int
}

struct SessionRow: Identifiable {
    let id:          Int64
    let appName:     String
    let windowTitle: String?
    let domain:      String?
    let category:    String
    let startedAt:   Date
    let endedAt:     Date
    let duration:    Double
    let keystrokes:  Int
    let clicks:      Int
    let isMeeting:   Bool
}

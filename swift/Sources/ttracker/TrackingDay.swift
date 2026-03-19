// TrackingDay.swift — Tracking-day boundary logic
// A new tracking day starts only when BOTH:
//   1. Gap since last activity > 5 hours
//   2. The calendar date has changed
// Late-night sessions therefore stay on the same tracking day.
// This logic is duplicated in report.py — keep them in sync.
import Foundation

private let ISO_FORMATTER: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone.current
    return f
}()

func isoToday() -> String {
    ISO_FORMATTER.string(from: Date())
}

func isoDate(_ date: Date) -> String {
    ISO_FORMATTER.string(from: date)
}

func dateFromISO(_ str: String) -> Date? {
    ISO_FORMATTER.date(from: str)
}

/// Compute the current tracking day.
///
/// - Parameters:
///   - lastActivityTS: Unix timestamp of the most-recently-saved session's ended_at.
///   - lastTrackingDay: The `tracking_day` column value of that same session.
///     Pass this when available — the session may have started before midnight, so
///     its `tracking_day` can differ from the calendar date of `lastActivityTS`.
/// - Returns: ISO-8601 date string for today's tracking day.
func getTrackingDay(lastActivityTS: Double?, lastTrackingDay: String?) -> String {
    let now   = Date()
    guard let lastTS = lastActivityTS else {
        return isoToday()
    }
    let gapHours = now.timeIntervalSince1970 - lastTS
    let gapH     = gapHours / 3600.0

    let today    = isoToday()
    var lastDate = lastTrackingDay ?? isoDate(Date(timeIntervalSince1970: lastTS))

    // Validate; fall back to today on parse error.
    if dateFromISO(lastDate) == nil { lastDate = today }

    if gapH > Settings.shared.trackingDayGapHours && today != lastDate {
        return today
    }
    return lastDate
}

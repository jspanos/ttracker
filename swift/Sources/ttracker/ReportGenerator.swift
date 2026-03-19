import Foundation

// Generates the full HTML report by querying the DB for all tracking days
// and injecting the data into the embedded HTML template.
final class ReportGenerator {

    let db: Database

    init(db: Database) { self.db = db }

    func generate() -> String {
        let allDays = db.getTrackingDaysSorted()  // sorted ascending (oldest first)
        guard !allDays.isEmpty else { return emptyHTML() }

        // Current tracking day
        let todayTD = allDays.last ?? ""

        // Build per-day data for each day
        var daysData: [String: Any] = [:]
        for day in allDays {
            daysData[day] = buildDayData(day: day)
        }

        // WEEK_TOTALS: tracking_day -> total active seconds
        var weekTotals: [String: Double] = [:]
        for (day, data) in daysData {
            if let d = data as? [String: Any],
               let byApp = d["todayByApp"] as? [[String: Any]] {
                weekTotals[day] = byApp.reduce(0.0) { $0 + (($1["total_seconds"] as? Double) ?? 0) }
            }
        }

        // App color map: sorted unique app names -> cycling 20-color palette
        let allApps = daysData.values.compactMap { $0 as? [String: Any] }
            .flatMap { d -> [String] in
                let byApp = d["todayByApp"] as? [[String: Any]] ?? []
                return byApp.compactMap { $0["app_name"] as? String }
            }
        let uniqueApps = Array(Set(allApps)).sorted()
        let palette = ["#4f86c6","#e07b39","#5bb56b","#c45c8a","#8b6fbe",
                       "#4bbfbf","#d4a040","#e05555","#7aaa44","#a060c0",
                       "#3a9abf","#bf7a3a","#5f9f5f","#9f5f9f","#bf9f3a",
                       "#5f7fbf","#bf5f5f","#5fbfbf","#9fbf5f","#7f5fbf"]
        var appColorsMap: [String: String] = [:]
        for (i, app) in uniqueApps.enumerated() {
            appColorsMap[app] = palette[i % palette.count]
        }

        let catColors: [String: String] = [
            "coding": "#4f86c6", "communication": "#e07b39", "browser": "#5bb56b",
            "media": "#c45c8a", "productivity": "#8b6fbe", "system": "#4bbfbf", "other": "#8892a4"
        ]

        // Serialize to JSON
        let daysJSON      = jsonString(daysData)
        let allDaysJSON   = jsonString(allDays)
        let todayJSON     = jsonString(todayTD)
        let appColorsJSON = jsonString(appColorsMap)
        let catColorsJSON = jsonString(catColors)
        let weekJSON      = jsonString(weekTotals)

        // Inject into template
        var html = reportHTMLTemplate
        html = html.replacingOccurrences(of: "__DAYS_DATA__",   with: daysJSON)
        html = html.replacingOccurrences(of: "__ALL_DAYS__",    with: allDaysJSON)
        html = html.replacingOccurrences(of: "__TODAY_TD__",    with: todayJSON)
        html = html.replacingOccurrences(of: "__APP_COLORS__",  with: appColorsJSON)
        html = html.replacingOccurrences(of: "__CAT_COLORS__",  with: catColorsJSON)
        html = html.replacingOccurrences(of: "__WEEK_TOTALS__", with: weekJSON)
        return html
    }

    private func buildDayData(day: String) -> [String: Any] {
        let dayStartTs = db.getDayStartTs(day)
        let (firstTs, lastTs) = db.getFirstLastTs(day)
        return [
            "todayByApp":    db.getAppUsage(day).map { ["app_name": $0.appName, "total_seconds": $0.duration] as [String: Any] },
            "byCategory":    db.getCategorySummary(day).map { ["category": $0.category, "total_seconds": $0.duration] as [String: Any] },
            "domains":       db.getDomains(day),
            "meetings":      db.getMeetingSummary(day),
            "meetingByApp":  db.getMeetingByApp(day),
            "timeline":      db.getTimeline(day),
            "inputByHour":   db.getInputByHour(day, dayStartTs: dayStartTs),
            "switchByHour":  db.getSwitchesByHour(day, dayStartTs: dayStartTs),
            "focusSessions": db.getFocusSessions(day),
            "allTitles":     db.getAllTitles(day),
            "inputTotals":   db.getInputTotals(day),
            "batteryHist":   db.getBatteryHistory(day),
            "switchFreq":    db.getSwitchFrequency(day),
            "projects":      db.getProjects(day),
            "dayStartTs":    dayStartTs,
            "firstTs":       firstTs.map { $0 as Any } ?? NSNull(),
            "lastTs":        lastTs.map  { $0 as Any } ?? NSNull(),
        ]
    }

    /// Recursively sanitize a value so NSJSONSerialization never sees non-serializable types.
    /// Replaces NaN/Inf Doubles with 0, Optional-wrapped values with their payload or NSNull,
    /// and drops any key whose value is not a recognized JSON-compatible type.
    private func sanitize(_ value: Any) -> Any {
        switch value {
        case let d as Double:
            return (d.isNaN || d.isInfinite) ? 0.0 : d
        case let f as Float:
            return (f.isNaN || f.isInfinite) ? 0.0 : Double(f)
        case let dict as [String: Any]:
            var out: [String: Any] = [:]
            for (k, v) in dict { out[k] = sanitize(v) }
            return out
        case let arr as [Any]:
            return arr.map { sanitize($0) }
        case is NSNull, is String, is Bool, is Int, is Int64, is UInt64:
            return value
        default:
            // Handle Swift Optional by reflecting — unwrap or return NSNull
            let mirror = Mirror(reflecting: value)
            if mirror.displayStyle == .optional {
                if let child = mirror.children.first { return sanitize(child.value) }
                return NSNull()
            }
            return NSNull()
        }
    }

    private func jsonString(_ value: Any) -> String {
        let safe = sanitize(value)
        // JSONSerialization only accepts top-level array/dict.
        // Handle scalars directly.
        switch safe {
        case is NSNull:
            return "null"
        case let s as String:
            let escaped = s
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\t", with: "\\t")
            return "\"\(escaped)\""
        case let b as Bool:
            return b ? "true" : "false"
        case let n as NSNumber:
            return n.stringValue
        default:
            guard JSONSerialization.isValidJSONObject(safe),
                  let data = try? JSONSerialization.data(withJSONObject: safe, options: [.sortedKeys]),
                  let str = String(data: data, encoding: .utf8) else { return "null" }
            return str
        }
    }

    private func emptyHTML() -> String {
        return "<html><body style='background:#0f1117;color:#e2e8f0;font-family:-apple-system;padding:40px;'><h2>No tracking data yet.</h2></body></html>"
    }
}

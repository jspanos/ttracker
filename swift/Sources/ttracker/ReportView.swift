import SwiftUI
import Charts

// MARK: - Root

struct ReportView: View {
    @StateObject private var vm: ReportViewModel

    init(db: Database) {
        _vm = StateObject(wrappedValue: ReportViewModel(db: db))
    }

    var body: some View {
        VStack(spacing: 0) {
            navBar
            Divider()
            if vm.isLoading {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.trackingDays.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        summaryCards
                        HStack(alignment: .top, spacing: 20) {
                            hourlyChart.frame(maxWidth: .infinity)
                            categoryChart.frame(width: 260)
                        }
                        topAppsChart
                        inputMetrics
                        sessionsSection
                    }
                    .padding(24)
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { vm.load() }
    }

    // MARK: Nav bar
    private var navBar: some View {
        HStack {
            Text("TTracker Report")
                .font(.title2).bold()
            Spacer()
            Button { vm.prevDay() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)
                .disabled(!vm.hasPreviousDay)
            Text(formattedDay)
                .font(.headline)
                .frame(width: 130, alignment: .center)
            Button { vm.nextDay() } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)
                .disabled(!vm.hasNextDay)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var formattedDay: String {
        guard let d = DateFormatter.iso.date(from: vm.selectedDay) else { return vm.selectedDay }
        return DateFormatter.display.string(from: d)
    }

    // MARK: Empty state
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.badge.questionmark").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("No data yet").font(.title3).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Summary cards
    private var summaryCards: some View {
        HStack(spacing: 16) {
            StatCard(label: "Active",     value: formatDuration(vm.summary.totalActiveSecs), icon: "clock.fill",          color: .blue)
            StatCard(label: "Sessions",   value: "\(vm.summary.sessionCount)",               icon: "square.stack.fill",   color: .indigo)
            StatCard(label: "Meetings",   value: "\(vm.summary.meetingCount)",               icon: "video.fill",          color: .orange)
            StatCard(label: "Keystrokes", value: formatCount(vm.summary.keystrokes),         icon: "keyboard.fill",       color: .green)
        }
    }

    // MARK: Hourly activity chart
    private var hourlyChart: some View {
        ChartCard(title: "Hourly Activity") {
            let buckets = filledHours
            Chart(buckets) { b in
                BarMark(x: .value("Hour", b.hour), y: .value("Min", b.activeSecs / 60))
                    .foregroundStyle(Color.blue.opacity(0.75))
                    .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { v in
                    AxisValueLabel { Text(hourLabel(v.as(Int.self) ?? 0)).font(.caption2) }
                    AxisGridLine()
                }
            }
            .chartYAxis {
                AxisMarks { v in
                    AxisValueLabel { Text("\(v.as(Int.self) ?? 0)m").font(.caption2) }
                    AxisGridLine()
                }
            }
            .frame(height: 160)
        }
    }

    private var filledHours: [HourlyBucket] {
        let map   = Dictionary(uniqueKeysWithValues: vm.hourlyActivity.map { ($0.hour, $0) })
        let first = vm.hourlyActivity.map(\.hour).min() ?? 9
        let last  = max(vm.hourlyActivity.map(\.hour).max() ?? 18, first)
        return (first...last).map { h in
            map[h] ?? HourlyBucket(id: h, hour: h, activeSecs: 0, keystrokes: 0)
        }
    }

    // MARK: Category chart
    private var categoryChart: some View {
        ChartCard(title: "By Category") {
            if vm.categories.isEmpty {
                Text("No data").foregroundStyle(.secondary).frame(height: 160)
            } else {
                Chart(vm.categories) { row in
                    BarMark(
                        x: .value("Min", row.duration / 60),
                        y: .value("Cat", row.category.capitalized)
                    )
                    .foregroundStyle(categoryColor(row.category))
                    .cornerRadius(3)
                }
                .chartXAxis {
                    AxisMarks { v in
                        AxisValueLabel { Text("\(v.as(Int.self) ?? 0)m").font(.caption2) }
                    }
                }
                .frame(height: 160)
            }
        }
    }

    // MARK: Top apps
    private var topAppsChart: some View {
        ChartCard(title: "Top Apps") {
            if vm.appUsage.isEmpty {
                Text("No data").foregroundStyle(.secondary)
            } else {
                Chart(Array(vm.appUsage.prefix(10))) { row in
                    BarMark(
                        x: .value("Min", row.duration / 60),
                        y: .value("App", row.appName)
                    )
                    .foregroundStyle(categoryColor(row.category))
                    .cornerRadius(3)
                    .annotation(position: .trailing, alignment: .leading) {
                        Text(formatDuration(row.duration)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks { v in
                        AxisValueLabel { Text(v.as(String.self) ?? "").font(.caption2) }
                    }
                }
                .frame(height: max(120, Double(min(vm.appUsage.count, 10)) * 28))
            }
        }
    }

    // MARK: Input metrics
    private var inputMetrics: some View {
        HStack(spacing: 16) {
            StatCard(label: "Clicks",   value: formatCount(vm.summary.clicks),                               icon: "cursorarrow.click.2",  color: .cyan)
            StatCard(label: "Scrolls",  value: formatCount(vm.summary.scrollEvents),                         icon: "scroll.fill",          color: .mint)
            StatCard(label: "Distance", value: String(format: "%.1f m", vm.summary.mouseDistMeters),         icon: "arrow.left.and.right", color: .teal)
        }
    }

    // MARK: Sessions
    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sessions").font(.headline)

            // Category filter pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterPill(label: "All",            selected: vm.selectedCategory == nil)    { vm.setCategory(nil) }
                    ForEach(["coding","communication","browser","media","productivity","system"], id: \.self) { cat in
                        FilterPill(label: cat.capitalized, selected: vm.selectedCategory == cat) { vm.setCategory(cat) }
                    }
                }
            }

            // Session rows
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Time").frame(width: 90, alignment: .leading).font(.caption).foregroundStyle(.secondary)
                    Text("App").frame(maxWidth: .infinity, alignment: .leading).font(.caption).foregroundStyle(.secondary)
                    Text("Title / URL").frame(maxWidth: .infinity, alignment: .leading).font(.caption).foregroundStyle(.secondary)
                    Text("Category").frame(width: 100, alignment: .leading).font(.caption).foregroundStyle(.secondary)
                    Text("Duration").frame(width: 70, alignment: .trailing).font(.caption).foregroundStyle(.secondary)
                    Text("Keys").frame(width: 50, alignment: .trailing).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                ForEach(Array(vm.sessions.enumerated()), id: \.element.id) { (i, row) in
                    SessionRowView(row: row)
                        .background(i % 2 == 0 ? Color.clear : Color(NSColor.controlBackgroundColor).opacity(0.4))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(NSColor.separatorColor), lineWidth: 1))

            // Pagination
            if vm.pageCount > 1 {
                HStack {
                    Button("← Prev") { vm.goToPage(vm.sessionPage - 1) }
                        .disabled(vm.sessionPage == 0)
                    Text("Page \(vm.sessionPage + 1) of \(vm.pageCount)")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Next →") { vm.goToPage(vm.sessionPage + 1) }
                        .disabled(vm.sessionPage >= vm.pageCount - 1)
                }
            }
        }
    }

    // MARK: Helpers
    private func hourLabel(_ h: Int) -> String {
        h == 0 ? "12a" : h < 12 ? "\(h)a" : h == 12 ? "12p" : "\(h-12)p"
    }
    private func formatCount(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n)/1000) : "\(n)"
    }
    private func categoryColor(_ cat: String) -> Color {
        switch cat {
        case "coding":        return .blue
        case "communication": return .orange
        case "browser":       return .cyan
        case "media":         return .purple
        case "productivity":  return .green
        case "system":        return Color(NSColor.systemGray)
        default:              return .indigo
        }
    }
}

// MARK: - Sub-views

struct StatCard: View {
    let label: String
    let value: String
    let icon:  String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.title3).bold()
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
    }
}

struct ChartCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
    }
}

struct FilterPill: View {
    let label:    String
    let selected: Bool
    let action:   () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(selected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                .foregroundStyle(selected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct SessionRowView: View {
    let row: SessionRow

    var body: some View {
        HStack {
            Text(timeStr)
                .font(.caption2).foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            HStack(spacing: 4) {
                if row.isMeeting { Image(systemName: "video.fill").foregroundStyle(.orange).font(.caption2) }
                Text(row.appName).font(.caption).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.domain ?? row.windowTitle ?? "")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.category.capitalized)
                .font(.caption2).foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(formatDuration(row.duration))
                .font(.caption2.monospacedDigit())
                .frame(width: 70, alignment: .trailing)
            Text(row.keystrokes > 0 ? "\(row.keystrokes)" : "—")
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private var timeStr: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: row.startedAt)
    }
}

// MARK: - DateFormatter helpers
private extension DateFormatter {
    static let iso: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    static let display: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f
    }()
}

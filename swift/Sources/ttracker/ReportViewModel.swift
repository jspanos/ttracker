import Foundation

@MainActor
final class ReportViewModel: ObservableObject {
    private let db: Database

    @Published var trackingDays:     [String]       = []
    @Published var selectedDay:      String         = isoToday()
    @Published var summary:          DaySummary     = DaySummary()
    @Published var appUsage:         [AppUsageRow]  = []
    @Published var categories:       [CategoryRow]  = []
    @Published var hourlyActivity:   [HourlyBucket] = []
    @Published var sessions:         [SessionRow]   = []
    @Published var sessionTotal:     Int            = 0
    @Published var sessionPage:      Int            = 0
    @Published var selectedCategory: String?        = nil
    @Published var isLoading:        Bool           = true

    let pageSize = 25

    init(db: Database) { self.db = db }

    var hasPreviousDay: Bool {
        guard let i = trackingDays.firstIndex(of: selectedDay) else { return false }
        return i + 1 < trackingDays.count
    }
    var hasNextDay: Bool {
        guard let i = trackingDays.firstIndex(of: selectedDay) else { return false }
        return i > 0
    }
    var pageCount: Int { max(1, (sessionTotal + pageSize - 1) / pageSize) }

    func load() {
        isLoading = true
        trackingDays = db.getTrackingDays()
        if !trackingDays.isEmpty && !trackingDays.contains(selectedDay) {
            selectedDay = trackingDays[0]
        }
        reloadAll()
    }

    func selectDay(_ day: String) {
        selectedDay = day; sessionPage = 0; selectedCategory = nil
        reloadAll()
    }
    func prevDay() {
        guard let i = trackingDays.firstIndex(of: selectedDay), i + 1 < trackingDays.count else { return }
        selectDay(trackingDays[i + 1])
    }
    func nextDay() {
        guard let i = trackingDays.firstIndex(of: selectedDay), i > 0 else { return }
        selectDay(trackingDays[i - 1])
    }
    func setCategory(_ cat: String?) {
        selectedCategory = cat; sessionPage = 0; reloadSessions()
    }
    func goToPage(_ p: Int) { sessionPage = p; reloadSessions() }

    private func reloadAll() {
        let day = selectedDay
        summary        = db.getDaySummary(day)
        appUsage       = db.getAppUsage(day)
        categories     = db.getCategorySummary(day)
        hourlyActivity = db.getHourlyActivity(day)
        let r = db.getSessions(day, category: selectedCategory, page: 0, pageSize: pageSize)
        sessions = r.rows; sessionTotal = r.total; sessionPage = 0
        isLoading = false
    }
    private func reloadSessions() {
        let r = db.getSessions(selectedDay, category: selectedCategory, page: sessionPage, pageSize: pageSize)
        sessions = r.rows; sessionTotal = r.total
    }
}

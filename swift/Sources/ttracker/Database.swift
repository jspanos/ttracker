// Database.swift — SQLite persistence layer for TTracker
// Schema is identical to the Python tracker for full data.db compatibility.
import Foundation
import SQLite3

// MARK: - SQLITE_TRANSIENT shim

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - Database

final class Database {

    // Serial queue serialises all DB access — never call SQLite from multiple threads.
    private let queue = DispatchQueue(label: "com.ttracker.database", qos: .utility)
    private var db: OpaquePointer?

    // MARK: Init / open

    init() {
        queue.sync { self.openAndMigrate() }
    }

    private func openAndMigrate() {
        // Ensure directory
        try? FileManager.default.createDirectory(at: DB_DIR,
                                                  withIntermediateDirectories: true)
        guard sqlite3_open(DB_PATH.path, &db) == SQLITE_OK else {
            print("[ttracker] Cannot open SQLite DB: \(String(cString: sqlite3_errmsg(db)))")
            return
        }
        sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil)
        createSchema()
        runMigrations()
    }

    // MARK: Schema creation

    private func createSchema() {
        let sql = """
        CREATE TABLE IF NOT EXISTS activities (
            id               INTEGER PRIMARY KEY AUTOINCREMENT,
            app_name         TEXT    NOT NULL,
            app_bundle_id    TEXT,
            app_category     TEXT,
            window_title     TEXT,
            url              TEXT,
            domain           TEXT,
            started_at       REAL    NOT NULL,
            ended_at         REAL    NOT NULL,
            duration_seconds REAL    NOT NULL,
            tracking_day     TEXT    NOT NULL DEFAULT '',
            is_idle          INTEGER DEFAULT 0,
            is_meeting       INTEGER DEFAULT 0,
            keystrokes       INTEGER DEFAULT 0,
            mouse_clicks     INTEGER DEFAULT 0,
            mouse_distance   REAL    DEFAULT 0,
            scroll_events    INTEGER DEFAULT 0,
            battery_percent  REAL,
            is_charging      INTEGER,
            tab_count        INTEGER
        );
        CREATE INDEX IF NOT EXISTS idx_act_day ON activities(tracking_day);
        CREATE INDEX IF NOT EXISTS idx_act_ts  ON activities(started_at);

        CREATE TABLE IF NOT EXISTS snapshots (
            id                   INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp            REAL    NOT NULL,
            tracking_day         TEXT    NOT NULL,
            app_name             TEXT,
            window_title         TEXT,
            url                  TEXT,
            domain               TEXT,
            app_category         TEXT,
            idle_seconds         REAL    DEFAULT 0,
            keystrokes_delta     INTEGER DEFAULT 0,
            mouse_clicks_delta   INTEGER DEFAULT 0,
            mouse_distance_delta REAL    DEFAULT 0,
            scroll_events_delta  INTEGER DEFAULT 0,
            battery_percent      REAL,
            is_charging          INTEGER,
            tab_count            INTEGER
        );
        CREATE INDEX IF NOT EXISTS idx_snap_ts  ON snapshots(timestamp);
        CREATE INDEX IF NOT EXISTS idx_snap_day ON snapshots(tracking_day);

        CREATE TABLE IF NOT EXISTS app_switches (
            id               INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp        REAL    NOT NULL,
            tracking_day     TEXT    NOT NULL,
            from_app         TEXT,
            to_app           TEXT    NOT NULL,
            time_in_from_app REAL
        );
        CREATE INDEX IF NOT EXISTS idx_sw_ts  ON app_switches(timestamp);
        CREATE INDEX IF NOT EXISTS idx_sw_day ON app_switches(tracking_day);

        CREATE TABLE IF NOT EXISTS tmux_events (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp     REAL    NOT NULL,
            tracking_day  TEXT    NOT NULL DEFAULT '',
            session_name  TEXT,
            window_index  TEXT,
            window_name   TEXT,
            pane_index    TEXT,
            pane_title    TEXT,
            pane_dir      TEXT,
            pane_cmd      TEXT,
            pane_count    INTEGER,
            pane_zoomed   INTEGER DEFAULT 0,
            window_count  INTEGER,
            session_count INTEGER,
            git_branch    TEXT,
            git_repo      TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_tmux_ts  ON tmux_events(timestamp);
        CREATE INDEX IF NOT EXISTS idx_tmux_day ON tmux_events(tracking_day);
        """
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let msg = errMsg {
                print("[ttracker] Schema error: \(String(cString: msg))")
                sqlite3_free(errMsg)
            }
        }
    }

    // MARK: Column-level migrations

    private func runMigrations() {
        let needed: [(String, String)] = [
            ("app_bundle_id",  "TEXT"),
            ("app_category",   "TEXT"),
            ("url",            "TEXT"),
            ("domain",         "TEXT"),
            ("tracking_day",   "TEXT NOT NULL DEFAULT ''"),
            ("is_idle",        "INTEGER DEFAULT 0"),
            ("is_meeting",     "INTEGER DEFAULT 0"),
            ("keystrokes",     "INTEGER DEFAULT 0"),
            ("mouse_clicks",   "INTEGER DEFAULT 0"),
            ("mouse_distance", "REAL DEFAULT 0"),
            ("scroll_events",  "INTEGER DEFAULT 0"),
            ("battery_percent","REAL"),
            ("is_charging",    "INTEGER"),
            ("tab_count",      "INTEGER"),
        ]
        var existing = Set<String>()
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA table_info(activities)", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let col = sqlite3_column_text(stmt, 1) {
                    existing.insert(String(cString: col))
                }
            }
        }
        sqlite3_finalize(stmt)

        for (col, typedef) in needed where !existing.contains(col) {
            let sql = "ALTER TABLE activities ADD COLUMN \(col) \(typedef)"
            sqlite3_exec(db, sql, nil, nil, nil)
        }
    }

    // MARK: - Save session

    func saveSession(
        appName:        String,
        bundleID:       String?,
        category:       String,
        windowTitle:    String?,
        url:            String?,
        domain:         String?,
        startedAt:      Double,
        endedAt:        Double,
        trackingDay:    String,
        isIdle:         Bool,
        isMeeting:      Bool,
        keystrokes:     Int,
        mouseClicks:    Int,
        mouseDistance:  Double,
        scrollEvents:   Int,
        battery:        BatteryInfo,
        tabCount:       Int?
    ) {
        let duration = endedAt - startedAt
        guard duration >= 1.0 else { return }

        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            let sql = """
            INSERT INTO activities
            (app_name,app_bundle_id,app_category,window_title,url,domain,
             started_at,ended_at,duration_seconds,tracking_day,
             is_idle,is_meeting,keystrokes,mouse_clicks,mouse_distance,
             scroll_events,battery_percent,is_charging,tab_count)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, appName, -1, SQLITE_TRANSIENT)
            self.bindOptText(stmt, 2, bundleID)
            sqlite3_bind_text(stmt, 3, category, -1, SQLITE_TRANSIENT)
            self.bindOptText(stmt, 4, windowTitle)
            self.bindOptText(stmt, 5, url)
            self.bindOptText(stmt, 6, domain)
            sqlite3_bind_double(stmt, 7, startedAt)
            sqlite3_bind_double(stmt, 8, endedAt)
            sqlite3_bind_double(stmt, 9, duration)
            sqlite3_bind_text(stmt, 10, trackingDay, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 11, isIdle    ? 1 : 0)
            sqlite3_bind_int(stmt, 12, isMeeting ? 1 : 0)
            sqlite3_bind_int(stmt, 13, Int32(keystrokes))
            sqlite3_bind_int(stmt, 14, Int32(mouseClicks))
            sqlite3_bind_double(stmt, 15, mouseDistance.rounded())
            sqlite3_bind_int(stmt, 16, Int32(scrollEvents))
            self.bindOptDouble(stmt, 17, battery.percent)
            if let c = battery.isCharging { sqlite3_bind_int(stmt, 18, c ? 1 : 0) }
            else { sqlite3_bind_null(stmt, 18) }
            if let tc = tabCount { sqlite3_bind_int(stmt, 19, Int32(tc)) }
            else { sqlite3_bind_null(stmt, 19) }

            if sqlite3_step(stmt) != SQLITE_DONE {
                print("[ttracker] saveSession error: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
    }

    // MARK: - Save snapshot

    func saveSnapshot(
        timestamp:           Double,
        trackingDay:         String,
        appName:             String?,
        windowTitle:         String?,
        url:                 String?,
        domain:              String?,
        category:            String?,
        idleSeconds:         Double,
        keystrokesDelta:     Int,
        mouseClicksDelta:    Int,
        mouseDistanceDelta:  Double,
        scrollEventsDelta:   Int,
        battery:             BatteryInfo,
        tabCount:            Int?
    ) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            let sql = """
            INSERT INTO snapshots
            (timestamp,tracking_day,app_name,window_title,url,domain,app_category,
             idle_seconds,keystrokes_delta,mouse_clicks_delta,mouse_distance_delta,
             scroll_events_delta,battery_percent,is_charging,tab_count)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_double(stmt, 1, timestamp)
            sqlite3_bind_text(stmt, 2, trackingDay, -1, SQLITE_TRANSIENT)
            self.bindOptText(stmt, 3, appName)
            self.bindOptText(stmt, 4, windowTitle)
            self.bindOptText(stmt, 5, url)
            self.bindOptText(stmt, 6, domain)
            self.bindOptText(stmt, 7, category)
            sqlite3_bind_double(stmt, 8, idleSeconds)
            sqlite3_bind_int(stmt, 9, Int32(keystrokesDelta))
            sqlite3_bind_int(stmt, 10, Int32(mouseClicksDelta))
            sqlite3_bind_double(stmt, 11, mouseDistanceDelta.rounded())
            sqlite3_bind_int(stmt, 12, Int32(scrollEventsDelta))
            self.bindOptDouble(stmt, 13, battery.percent)
            if let c = battery.isCharging { sqlite3_bind_int(stmt, 14, c ? 1 : 0) }
            else { sqlite3_bind_null(stmt, 14) }
            if let tc = tabCount { sqlite3_bind_int(stmt, 15, Int32(tc)) }
            else { sqlite3_bind_null(stmt, 15) }

            sqlite3_step(stmt)
        }
    }

    // MARK: - Save app switch

    func saveAppSwitch(
        timestamp:      Double,
        trackingDay:    String,
        fromApp:        String?,
        toApp:          String,
        timeInFromApp:  Double?
    ) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            let sql = """
            INSERT INTO app_switches (timestamp,tracking_day,from_app,to_app,time_in_from_app)
            VALUES (?,?,?,?,?)
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_double(stmt, 1, timestamp)
            sqlite3_bind_text(stmt, 2, trackingDay, -1, SQLITE_TRANSIENT)
            self.bindOptText(stmt, 3, fromApp)
            sqlite3_bind_text(stmt, 4, toApp, -1, SQLITE_TRANSIENT)
            if let t = timeInFromApp { sqlite3_bind_double(stmt, 5, t) }
            else { sqlite3_bind_null(stmt, 5) }
            sqlite3_step(stmt)
        }
    }

    // MARK: - Save telemetry event

    func saveTelemetryEvent(_ event: [String: Any]) {
        let ts    = (event["timestamp"] as? Double) ?? Date().timeIntervalSince1970
        let td    = getTrackingDay(lastActivityTS: ts, lastTrackingDay: nil)
        let state = TelemetryState(from: event)

        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            let sql = """
            INSERT INTO tmux_events
            (timestamp,tracking_day,session_name,window_index,window_name,
             pane_index,pane_title,pane_dir,pane_cmd,pane_count,pane_zoomed,
             window_count,session_count,git_branch,git_repo)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_double(stmt, 1, ts)
            sqlite3_bind_text(stmt, 2, td, -1, SQLITE_TRANSIENT)
            self.bindOptText(stmt, 3, state.sessionName)
            self.bindOptText(stmt, 4, state.windowIndex)
            self.bindOptText(stmt, 5, state.windowName)
            self.bindOptText(stmt, 6, state.paneIndex)
            self.bindOptText(stmt, 7, state.paneTitle)
            self.bindOptText(stmt, 8, state.paneDir)
            self.bindOptText(stmt, 9, state.paneCmd)
            if let pc = state.paneCount { sqlite3_bind_int(stmt, 10, Int32(pc)) }
            else { sqlite3_bind_null(stmt, 10) }
            sqlite3_bind_int(stmt, 11, state.paneZoomed ? 1 : 0)
            if let wc = state.windowCount  { sqlite3_bind_int(stmt, 12, Int32(wc)) }
            else { sqlite3_bind_null(stmt, 12) }
            if let sc = state.sessionCount { sqlite3_bind_int(stmt, 13, Int32(sc)) }
            else { sqlite3_bind_null(stmt, 13) }
            self.bindOptText(stmt, 14, state.gitBranch)
            self.bindOptText(stmt, 15, state.gitRepo)
            sqlite3_step(stmt)
        }
    }

    // MARK: - Synchronous queries

    func getTodayTotalSeconds(trackingDay: String) -> Double {
        var result: Double = 0
        queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            let sql = "SELECT SUM(duration_seconds) FROM activities WHERE tracking_day=? AND is_idle=0"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, trackingDay, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                result = sqlite3_column_double(stmt, 0)
            }
        }
        return result
    }

    func getTodayTopApp(trackingDay: String) -> String? {
        var result: String?
        queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            let sql = """
            SELECT app_name FROM activities WHERE tracking_day=? AND is_idle=0
            GROUP BY app_name ORDER BY SUM(duration_seconds) DESC LIMIT 1
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, trackingDay, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW, let t = sqlite3_column_text(stmt, 0) {
                result = String(cString: t)
            }
        }
        return result
    }

    func getLastSession() -> (endedAt: Double, trackingDay: String)? {
        var result: (Double, String)?
        queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            let sql = "SELECT ended_at, tracking_day FROM activities ORDER BY ended_at DESC LIMIT 1"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            if sqlite3_step(stmt) == SQLITE_ROW {
                let ended = sqlite3_column_double(stmt, 0)
                let day   = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                result = (ended, day)
            }
        }
        return result
    }

    /// Returns active duration and first session start, restricted to sessions
    /// that started at or after `since`. This keeps the audit scoped to the
    /// current tracker instance so gaps from before a restart don't inflate
    /// the discrepancy.
    func getDayAuditStats(trackingDay: String, since: Double) -> (totalDuration: Double, firstStart: Double?) {
        var total: Double  = 0
        var first: Double? = nil
        queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            let sql = "SELECT SUM(duration_seconds), MIN(started_at) FROM activities WHERE tracking_day=? AND started_at >= ?"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, trackingDay, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, since)
            if sqlite3_step(stmt) == SQLITE_ROW {
                total = sqlite3_column_double(stmt, 0)
                if sqlite3_column_type(stmt, 1) != SQLITE_NULL {
                    first = sqlite3_column_double(stmt, 1)
                }
            }
        }
        return (total, first)
    }

    // MARK: Private helpers

    private func bindOptText(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String?) {
        if let v = value { sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT) }
        else             { sqlite3_bind_null(stmt, idx) }
    }

    private func bindOptDouble(_ stmt: OpaquePointer?, _ idx: Int32, _ value: Double?) {
        if let v = value { sqlite3_bind_double(stmt, idx, v) }
        else             { sqlite3_bind_null(stmt, idx) }
    }

    // MARK: - Report Queries

    func getTrackingDays() -> [String] {
        var result: [String] = []
        queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            let sql = "SELECT DISTINCT tracking_day FROM activities ORDER BY tracking_day DESC"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let t = sqlite3_column_text(stmt, 0) {
                    result.append(String(cString: t))
                }
            }
        }
        return result
    }

    func getDaySummary(_ day: String) -> DaySummary {
        var summary = DaySummary()
        queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            let sql = """
            SELECT
                SUM(duration_seconds),
                COUNT(*),
                SUM(CASE WHEN is_meeting=1 THEN 1 ELSE 0 END),
                SUM(keystrokes),
                SUM(mouse_clicks),
                SUM(mouse_distance),
                SUM(scroll_events)
            FROM activities
            WHERE tracking_day=? AND is_idle=0
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, day, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                summary.totalActiveSecs  = sqlite3_column_double(stmt, 0)
                summary.sessionCount     = Int(sqlite3_column_int(stmt, 1))
                summary.meetingCount     = Int(sqlite3_column_int(stmt, 2))
                summary.keystrokes       = Int(sqlite3_column_int(stmt, 3))
                summary.clicks           = Int(sqlite3_column_int(stmt, 4))
                summary.mouseDistMeters  = sqlite3_column_double(stmt, 5)
                summary.scrollEvents     = Int(sqlite3_column_int(stmt, 6))
            }
        }
        return summary
    }

    func getAppUsage(_ day: String) -> [AppUsageRow] {
        var result: [AppUsageRow] = []
        queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            let sql = """
            SELECT
                app_name,
                COALESCE(NULLIF(app_category,''),'other') AS category,
                SUM(duration_seconds) AS total_dur,
                COUNT(*) AS session_count
            FROM activities
            WHERE tracking_day=? AND is_idle=0
            GROUP BY app_name
            ORDER BY total_dur DESC
            LIMIT 15
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, day, -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let appName  = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                let category = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "other"
                let duration = sqlite3_column_double(stmt, 2)
                let sessions = Int(sqlite3_column_int(stmt, 3))
                result.append(AppUsageRow(appName: appName, category: category, duration: duration, sessions: sessions))
            }
        }
        return result
    }

    // Fix sort order: ascending (oldest first)
    func getTrackingDaysSorted() -> [String] {
        var result: [String] = []
        queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            let sql = "SELECT DISTINCT tracking_day FROM activities WHERE tracking_day != '' ORDER BY tracking_day ASC"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let t = sqlite3_column_text(stmt, 0) {
                    result.append(String(cString: t))
                }
            }
        }
        return result
    }

    func getCategorySummary(_ day: String) -> [CategoryRow] {
        var result: [CategoryRow] = []
        queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            let sql = """
            SELECT
                COALESCE(NULLIF(app_category,''),'other') AS category,
                SUM(duration_seconds) AS total_dur,
                COUNT(*) AS session_count
            FROM activities
            WHERE tracking_day=? AND is_idle=0
            GROUP BY category
            ORDER BY total_dur DESC
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, day, -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let category = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? "other"
                let duration = sqlite3_column_double(stmt, 1)
                let sessions = Int(sqlite3_column_int(stmt, 2))
                result.append(CategoryRow(category: category, duration: duration, sessions: sessions))
            }
        }
        return result
    }

    func getHourlyActivity(_ day: String) -> [HourlyBucket] {
        var result: [HourlyBucket] = []
        queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            let sql = """
            SELECT
                CAST(strftime('%H', datetime(started_at,'unixepoch','localtime')) AS INTEGER) AS hour,
                SUM(duration_seconds) AS active_secs,
                SUM(keystrokes) AS total_keys
            FROM activities
            WHERE tracking_day=? AND is_idle=0
            GROUP BY hour
            ORDER BY hour
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, day, -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let hour       = Int(sqlite3_column_int(stmt, 0))
                let activeSecs = sqlite3_column_double(stmt, 1)
                let keystrokes = Int(sqlite3_column_int(stmt, 2))
                result.append(HourlyBucket(id: hour, hour: hour, activeSecs: activeSecs, keystrokes: keystrokes))
            }
        }
        return result
    }

    func getSessions(_ day: String, category: String?, page: Int, pageSize: Int) -> (rows: [SessionRow], total: Int) {
        if let cat = category {
            return getSessionsFiltered(day: day, category: cat, page: page, pageSize: pageSize)
        } else {
            return getSessionsAll(day: day, page: page, pageSize: pageSize)
        }
    }

    private func getSessionsAll(day: String, page: Int, pageSize: Int) -> (rows: [SessionRow], total: Int) {
        var total = 0
        var rows: [SessionRow] = []
        queue.sync {
            guard let db else { return }
            // Count
            var cStmt: OpaquePointer?
            let countSQL = "SELECT COUNT(*) FROM activities WHERE tracking_day=? AND is_idle=0"
            if sqlite3_prepare_v2(db, countSQL, -1, &cStmt, nil) == SQLITE_OK {
                defer { sqlite3_finalize(cStmt) }
                sqlite3_bind_text(cStmt, 1, day, -1, SQLITE_TRANSIENT)
                if sqlite3_step(cStmt) == SQLITE_ROW {
                    total = Int(sqlite3_column_int(cStmt, 0))
                }
            }
            // Data
            var stmt: OpaquePointer?
            let sql = """
            SELECT id, app_name, window_title, domain,
                   COALESCE(NULLIF(app_category,''),'other'),
                   started_at, ended_at, duration_seconds,
                   keystrokes, mouse_clicks, is_meeting
            FROM activities
            WHERE tracking_day=? AND is_idle=0
            ORDER BY started_at DESC
            LIMIT ? OFFSET ?
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, day, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 2, Int32(pageSize))
            sqlite3_bind_int(stmt, 3, Int32(page * pageSize))
            rows = collectSessionRows(stmt)
        }
        return (rows, total)
    }

    private func getSessionsFiltered(day: String, category: String, page: Int, pageSize: Int) -> (rows: [SessionRow], total: Int) {
        var total = 0
        var rows: [SessionRow] = []
        queue.sync {
            guard let db else { return }
            // Count
            var cStmt: OpaquePointer?
            let countSQL = """
            SELECT COUNT(*) FROM activities
            WHERE tracking_day=? AND is_idle=0
              AND COALESCE(NULLIF(app_category,''),'other')=?
            """
            if sqlite3_prepare_v2(db, countSQL, -1, &cStmt, nil) == SQLITE_OK {
                defer { sqlite3_finalize(cStmt) }
                sqlite3_bind_text(cStmt, 1, day, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(cStmt, 2, category, -1, SQLITE_TRANSIENT)
                if sqlite3_step(cStmt) == SQLITE_ROW {
                    total = Int(sqlite3_column_int(cStmt, 0))
                }
            }
            // Data
            var stmt: OpaquePointer?
            let sql = """
            SELECT id, app_name, window_title, domain,
                   COALESCE(NULLIF(app_category,''),'other'),
                   started_at, ended_at, duration_seconds,
                   keystrokes, mouse_clicks, is_meeting
            FROM activities
            WHERE tracking_day=? AND is_idle=0
              AND COALESCE(NULLIF(app_category,''),'other')=?
            ORDER BY started_at DESC
            LIMIT ? OFFSET ?
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, day, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, category, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 3, Int32(pageSize))
            sqlite3_bind_int(stmt, 4, Int32(page * pageSize))
            rows = collectSessionRows(stmt)
        }
        return (rows, total)
    }

    // MARK: - Report Generator Queries

    func getDayStartTs(_ day: String) -> Double {
        var result: Double = 0
        queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            let sql = "SELECT MIN(started_at) FROM activities WHERE tracking_day=?"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, day, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_type(stmt, 0) != SQLITE_NULL {
                result = sqlite3_column_double(stmt, 0)
            }
        }
        return result
    }

    func getFirstLastTs(_ day: String) -> (first: Double?, last: Double?) {
        var first: Double? = nil
        var last:  Double? = nil
        queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            let sql = "SELECT MIN(started_at), MAX(ended_at) FROM activities WHERE tracking_day=? AND is_idle=0"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, day, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                if sqlite3_column_type(stmt, 0) != SQLITE_NULL { first = sqlite3_column_double(stmt, 0) }
                if sqlite3_column_type(stmt, 1) != SQLITE_NULL { last  = sqlite3_column_double(stmt, 1) }
            }
        }
        return (first, last)
    }

    func getTimeline(_ day: String) -> [[String: Any]] {
        var result: [[String: Any]] = []
        queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            let sql = """
            SELECT app_name, window_title, url, domain,
                   COALESCE(app_category,'other') AS category,
                   started_at, ended_at, duration_seconds, is_meeting, is_idle
            FROM activities WHERE tracking_day=? ORDER BY started_at
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, day, -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                var row: [String: Any] = [:]
                row["app_name"]         = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                row["window_title"]     = sqlite3_column_text(stmt, 1).map { String(cString: $0) } as Any? ?? NSNull()
                row["url"]              = sqlite3_column_text(stmt, 2).map { String(cString: $0) } as Any? ?? NSNull()
                row["domain"]           = sqlite3_column_text(stmt, 3).map { String(cString: $0) } as Any? ?? NSNull()
                row["category"]         = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? "other"
                row["started_at"]       = sqlite3_column_double(stmt, 5)
                row["ended_at"]         = sqlite3_column_double(stmt, 6)
                row["duration_seconds"] = sqlite3_column_double(stmt, 7)
                row["is_meeting"]       = Int(sqlite3_column_int(stmt, 8))
                row["is_idle"]          = Int(sqlite3_column_int(stmt, 9))
                result.append(row)
            }
        }
        return result
    }

    func getInputByHour(_ day: String, dayStartTs: Double) -> [[String: Any]] {
        var result: [[String: Any]] = []
        queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            let sql = """
            SELECT CAST((timestamp - ?) / 3600 AS INTEGER) AS hour_idx,
                   SUM(keystrokes_delta) AS keystrokes,
                   SUM(mouse_clicks_delta) AS clicks,
                   SUM(scroll_events_delta) AS scrolls
            FROM snapshots WHERE tracking_day=?
            GROUP BY hour_idx ORDER BY hour_idx
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_double(stmt, 1, dayStartTs)
            sqlite3_bind_text(stmt, 2, day, -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                var row: [String: Any] = [:]
                row["hour_idx"]   = Int(sqlite3_column_int(stmt, 0))
                row["keystrokes"] = Int(sqlite3_column_int(stmt, 1))
                row["clicks"]     = Int(sqlite3_column_int(stmt, 2))
                row["scrolls"]    = Int(sqlite3_column_int(stmt, 3))
                result.append(row)
            }
        }
        return result
    }

    func getSwitchesByHour(_ day: String, dayStartTs: Double) -> [[String: Any]] {
        var result: [[String: Any]] = []
        queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            let sql = """
            SELECT CAST((timestamp - ?) / 3600 AS INTEGER) AS hour_idx,
                   COUNT(*) AS switch_count
            FROM app_switches WHERE tracking_day=?
            GROUP BY hour_idx ORDER BY hour_idx
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_double(stmt, 1, dayStartTs)
            sqlite3_bind_text(stmt, 2, day, -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                var row: [String: Any] = [:]
                row["hour_idx"]     = Int(sqlite3_column_int(stmt, 0))
                row["switch_count"] = Int(sqlite3_column_int(stmt, 1))
                result.append(row)
            }
        }
        return result
    }

    func getFocusSessions(_ day: String) -> [[String: Any]] {
        var result: [[String: Any]] = []
        queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            let sql = """
            SELECT app_name, COALESCE(app_category,'other') AS category,
                   window_title, url, started_at, ended_at, duration_seconds,
                   keystrokes, mouse_clicks
            FROM activities WHERE tracking_day=? AND is_idle=0
            ORDER BY duration_seconds DESC LIMIT 10
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, day, -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                var row: [String: Any] = [:]
                row["app_name"]         = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                row["category"]         = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "other"
                row["window_title"]     = sqlite3_column_text(stmt, 2).map { String(cString: $0) } as Any? ?? NSNull()
                row["url"]              = sqlite3_column_text(stmt, 3).map { String(cString: $0) } as Any? ?? NSNull()
                row["started_at"]       = sqlite3_column_double(stmt, 4)
                row["ended_at"]         = sqlite3_column_double(stmt, 5)
                row["duration_seconds"] = sqlite3_column_double(stmt, 6)
                row["keystrokes"]       = Int(sqlite3_column_int(stmt, 7))
                row["mouse_clicks"]     = Int(sqlite3_column_int(stmt, 8))
                result.append(row)
            }
        }
        return result
    }

    func getAllTitles(_ day: String) -> [[String: Any]] {
        var result: [[String: Any]] = []
        queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            let sql = """
            SELECT app_name, COALESCE(app_category,'other') AS category,
                   window_title, url, domain,
                   SUM(duration_seconds) AS total_seconds,
                   SUM(keystrokes) AS keystrokes,
                   SUM(mouse_clicks) AS mouse_clicks
            FROM activities WHERE tracking_day=? AND is_idle=0
            GROUP BY app_name, window_title
            ORDER BY total_seconds DESC LIMIT 50
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, day, -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                var row: [String: Any] = [:]
                row["app_name"]       = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                row["category"]       = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "other"
                row["window_title"]   = sqlite3_column_text(stmt, 2).map { String(cString: $0) } as Any? ?? NSNull()
                row["url"]            = sqlite3_column_text(stmt, 3).map { String(cString: $0) } as Any? ?? NSNull()
                row["domain"]         = sqlite3_column_text(stmt, 4).map { String(cString: $0) } as Any? ?? NSNull()
                row["total_seconds"]  = sqlite3_column_double(stmt, 5)
                row["keystrokes"]     = Int(sqlite3_column_int(stmt, 6))
                row["mouse_clicks"]   = Int(sqlite3_column_int(stmt, 7))
                result.append(row)
            }
        }
        return result
    }

    func getInputTotals(_ day: String) -> [String: Any] {
        var result: [String: Any] = ["keystrokes": 0, "clicks": 0, "distance_m": 0.0, "scrolls": 0]
        queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            let sql = """
            SELECT SUM(keystrokes), SUM(mouse_clicks), SUM(mouse_distance), SUM(scroll_events)
            FROM activities WHERE tracking_day=? AND is_idle=0
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, day, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                result["keystrokes"]  = Int(sqlite3_column_int(stmt, 0))
                result["clicks"]      = Int(sqlite3_column_int(stmt, 1))
                let distPx            = sqlite3_column_double(stmt, 2)
                result["distance_m"]  = distPx * 0.00025
                result["scrolls"]     = Int(sqlite3_column_int(stmt, 3))
            }
        }
        return result
    }

    func getBatteryHistory(_ day: String) -> [[String: Any]] {
        var result: [[String: Any]] = []
        queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            let sql = """
            SELECT timestamp, battery_percent, is_charging
            FROM snapshots WHERE tracking_day=? AND battery_percent IS NOT NULL
            ORDER BY timestamp
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, day, -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                var row: [String: Any] = [:]
                row["timestamp"]       = sqlite3_column_double(stmt, 0)
                row["battery_percent"] = sqlite3_column_double(stmt, 1)
                row["is_charging"]     = sqlite3_column_type(stmt, 2) != SQLITE_NULL
                    ? Int(sqlite3_column_int(stmt, 2)) : NSNull()
                result.append(row)
            }
        }
        return result
    }

    func getSwitchFrequency(_ day: String) -> [[String: Any]] {
        var result: [[String: Any]] = []
        queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            let sql = """
            SELECT to_app AS app_name, COUNT(*) AS switch_count,
                   AVG(time_in_from_app) AS avg_time_before_switch
            FROM app_switches WHERE tracking_day=?
            GROUP BY to_app ORDER BY switch_count DESC LIMIT 10
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, day, -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                var row: [String: Any] = [:]
                row["app_name"]               = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                row["switch_count"]           = Int(sqlite3_column_int(stmt, 1))
                row["avg_time_before_switch"] = sqlite3_column_type(stmt, 2) != SQLITE_NULL
                    ? sqlite3_column_double(stmt, 2) : NSNull()
                result.append(row)
            }
        }
        return result
    }

    func getDomains(_ day: String) -> [[String: Any]] {
        var result: [[String: Any]] = []
        queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            let sql = """
            SELECT domain, SUM(duration_seconds) AS total_seconds
            FROM activities WHERE tracking_day=? AND is_idle=0
              AND domain IS NOT NULL AND domain != ''
            GROUP BY domain ORDER BY total_seconds DESC LIMIT 15
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, day, -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                var row: [String: Any] = [:]
                row["domain"]        = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                row["total_seconds"] = sqlite3_column_double(stmt, 1)
                result.append(row)
            }
        }
        return result
    }

    func getMeetingSummary(_ day: String) -> [String: Any] {
        var result: [String: Any] = ["total_seconds": 0.0, "session_count": 0]
        queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            let sql = "SELECT SUM(duration_seconds), COUNT(*) FROM activities WHERE tracking_day=? AND is_meeting=1"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, day, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                result["total_seconds"]  = sqlite3_column_double(stmt, 0)
                result["session_count"]  = Int(sqlite3_column_int(stmt, 1))
            }
        }
        return result
    }

    func getMeetingByApp(_ day: String) -> [[String: Any]] {
        var result: [[String: Any]] = []
        queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            let sql = """
            SELECT app_name, SUM(duration_seconds) AS total_seconds, COUNT(*) AS session_count
            FROM activities WHERE tracking_day=? AND is_meeting=1 AND is_idle=0
            GROUP BY app_name ORDER BY total_seconds DESC
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, day, -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                var row: [String: Any] = [:]
                row["app_name"]      = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                row["total_seconds"] = sqlite3_column_double(stmt, 1)
                row["session_count"] = Int(sqlite3_column_int(stmt, 2))
                result.append(row)
            }
        }
        return result
    }

    func getProjects(_ day: String) -> [[String: Any]] {
        // Check if tmux_events table has data for this day
        var hasTmux = false
        queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            let sql = "SELECT COUNT(*) FROM tmux_events WHERE tracking_day=?"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, day, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_int(stmt, 0) > 0 {
                hasTmux = true
            }
        }

        var result: [[String: Any]] = []
        queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            let sql: String
            if hasTmux {
                sql = """
                SELECT COALESCE(git_repo, pane_dir, 'unknown') AS project,
                       SUM(duration_seconds) AS total_seconds
                FROM activities a
                JOIN (SELECT DISTINCT pane_dir, git_repo FROM tmux_events WHERE tracking_day=?) t
                  ON a.app_name IN ('iTerm2','Terminal','Alacritty','kitty','Warp','Hyper','WezTerm')
                WHERE a.tracking_day=? AND a.is_idle=0
                GROUP BY project ORDER BY total_seconds DESC
                """
            } else {
                sql = """
                SELECT window_title AS project, SUM(duration_seconds) AS total_seconds
                FROM activities WHERE tracking_day=? AND is_idle=0
                  AND app_name IN ('iTerm2','Terminal','Alacritty','kitty','Warp','Hyper','WezTerm')
                GROUP BY window_title ORDER BY total_seconds DESC
                """
            }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            if hasTmux {
                sqlite3_bind_text(stmt, 1, day, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, day, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_text(stmt, 1, day, -1, SQLITE_TRANSIENT)
            }
            while sqlite3_step(stmt) == SQLITE_ROW {
                var row: [String: Any] = [:]
                row["project"]       = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                row["total_seconds"] = sqlite3_column_double(stmt, 1)
                result.append(row)
            }
        }
        return result
    }

    /// Must be called from within queue.sync block.
    private func collectSessionRows(_ stmt: OpaquePointer?) -> [SessionRow] {
        var rows: [SessionRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id          = sqlite3_column_int64(stmt, 0)
            let appName     = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let windowTitle = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            let domain      = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
            let category    = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? "other"
            let startedAt   = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
            let endedAt     = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6))
            let duration    = sqlite3_column_double(stmt, 7)
            let keystrokes  = Int(sqlite3_column_int(stmt, 8))
            let clicks      = Int(sqlite3_column_int(stmt, 9))
            let isMeeting   = sqlite3_column_int(stmt, 10) != 0
            rows.append(SessionRow(
                id: id,
                appName: appName,
                windowTitle: windowTitle,
                domain: domain,
                category: category,
                startedAt: startedAt,
                endedAt: endedAt,
                duration: duration,
                keystrokes: keystrokes,
                clicks: clicks,
                isMeeting: isMeeting
            ))
        }
        return rows
    }
}

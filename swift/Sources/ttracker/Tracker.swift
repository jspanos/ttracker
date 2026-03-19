// Tracker.swift — Core session state machine
// All mutable state lives here and is accessed exclusively on `stateQueue`.
import AppKit
import Foundation

final class Tracker {

    // MARK: Dependencies

    let db:             Database
    let inputMonitor:   InputMonitor
    let sleepWake:      SleepWakeMonitor
    let telemetry:      TelemetryServer

    // MARK: Callbacks for the status bar

    /// Called after every poll to refresh the menu bar display.
    var onRefresh: ((_ activity: Activity?, _ totalSecs: Double, _ isIdle: Bool) -> Void)?
    /// Called when an audit log line is ready (optional; already written to file).
    var onAudit: ((String) -> Void)?

    // MARK: Session state — all access on stateQueue

    private let stateQueue = DispatchQueue(label: "com.ttracker.state")

    private var paused    = false
    private var isIdle    = false
    private var lastPollTime: TimeInterval = 0

    private var sess:         Activity?  = nil
    private var sessStart:    Double     = 0
    private var sessCtrBase:  InputCounters = InputCounters()

    private var idleEnteredAt:  Double? = nil
    private var todayIdleSecs:  Double  = 0

    private var trackingDay:    String  = isoToday()
    private var milestoneSent:  Set<Int> = []
    private var sleptAt:        Double  = 0   // timestamp of last sleep notification

    private var lastBattery:    BatteryInfo    = .unknown

    private var snapCtrBase:    InputCounters  = InputCounters()
    private var lastNotifTS:    Double         = 0
    private var auditStartTS:   Double         = 0   // set when tracker starts; audit only counts sessions since this time

    // MARK: Background-cached system state (never block the main thread)

    private let audioLock         = NSLock()
    private var _audioActive      = false
    private var cachedAudioActive: Bool {
        audioLock.lock(); defer { audioLock.unlock() }; return _audioActive
    }

    private let batteryLock    = NSLock()
    private var _cachedBattery: BatteryInfo = .unknown
    private var cachedBattery: BatteryInfo {
        batteryLock.lock(); defer { batteryLock.unlock() }; return _cachedBattery
    }

    private let audioRefreshQ   = DispatchQueue(label: "com.ttracker.audio",   qos: .utility)
    private let batteryRefreshQ = DispatchQueue(label: "com.ttracker.battery", qos: .utility)

    // MARK: Work limit state (access on stateQueue)

    private(set) var workLimit: WorkLimit? = nil
    private var limitBlinkOn = true

    // MARK: Telemetry state

    private var telemetryStateLock = NSLock()
    private var telemetryState: TelemetryState? = nil
    private var isBootingTelemetry = false  // true during drainQueue phase

    // MARK: Timers

    private var pollTimer:     Timer?
    private var snapshotTimer: Timer?
    private var countdownTimer: Timer?
    private var pollInFlight   = false   // prevent overlapping AppleScript calls
    private let activityQueue  = DispatchQueue(label: "com.ttracker.activity", qos: .userInitiated)

    // MARK: Init

    init() {
        db           = Database()
        inputMonitor = InputMonitor()
        sleepWake    = SleepWakeMonitor()
        telemetry    = TelemetryServer()
    }

    // MARK: Start

    func start() {
        inputMonitor.start()

        sleepWake.onSleep = { [weak self] in self?.handleSleep() }
        sleepWake.onWake  = { [weak self] in self?.handleWake()  }
        sleepWake.start()

        // Telemetry server
        telemetry.onEvent = { [weak self] event in
            guard let self else { return }
            self.db.saveTelemetryEvent(event)
            // Only update in-memory state when a terminal app is frontmost.
            if self.isTerminalFrontmost() {
                let state = TelemetryState(from: event)
                self.telemetryStateLock.lock()
                self.telemetryState = state
                self.telemetryStateLock.unlock()
            }
        }
        telemetry.start()

        auditStartTS = Date().timeIntervalSince1970
        auditLog("TRACKER_START  (idle counter reset; discrepancy before this line may include pre-restart idle)")

        // Seed caches immediately, then keep refreshing in background.
        startBackgroundRefreshes()

        // Fire timers on main run loop.
        DispatchQueue.main.async { self.startTimers() }
    }

    private func startTimers() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: POLL_INTERVAL,
                                         repeats: true) { [weak self] _ in
            self?.poll()
        }
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: SNAPSHOT_INTERVAL,
                                              repeats: true) { [weak self] _ in
            self?.snapshot()
        }
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0,
                                               repeats: true) { [weak self] _ in
            self?.countdownTick()
        }
        // Fire immediately on start
        poll()
    }

    // MARK: - Poll (every 5 s)

    func poll() {
        guard !paused else { return }
        // Prevent overlapping polls if a previous AppleScript call is still running.
        guard !pollInFlight else { return }
        pollInFlight = true

        // Capture timing on the main thread immediately — don't let async delay skew these.
        let idleSecs  = getIdleSeconds()
        let now       = Date().timeIntervalSince1970
        let prevPoll  = lastPollTime
        lastPollTime  = now

        let currentTelemetry: TelemetryState?
        telemetryStateLock.lock()
        currentTelemetry = telemetryState
        telemetryStateLock.unlock()

        // Move the blocking AppleScript calls off the main thread.
        activityQueue.async { [weak self] in
            guard let self else { return }

            var activity = getCurrentActivity(telemetryState: currentTelemetry)
            let audioActive = self.cachedAudioActive

            if !activity.isMeeting && audioActive && CALL_AUDIO_APPS.contains(activity.appName) {
                activity.isMeeting = true
            }

            let threshold = Settings.shared.idleThresholdSeconds
            let userIdle  = idleSecs >= threshold &&
                            (!Settings.shared.audioSuppressesIdle || !audioActive)

            // State machine and UI callbacks must run on the main thread.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                defer { self.pollInFlight = false }

                self.stateQueue.sync {
                    if userIdle {
                        if !self.isIdle {
                            let closeAt: Double
                            if self.sessStart > 0 {
                                let idleStarted = now - idleSecs
                                closeAt = max(idleStarted, self.sessStart + 1.0)
                            } else {
                                closeAt = now
                            }
                            self.closeSession(endedAt: closeAt)
                            self.resetSession()
                            self.idleEnteredAt = now - idleSecs
                            auditLog("IDLE_ENTER")
                        }
                        self.isIdle = true

                        if idleSecs >= 600 && self.workLimit != nil {
                            self.workLimit = nil
                            self.limitBlinkOn = true
                        }
                    } else {
                        if self.isIdle {
                            self.isIdle = false
                            self.resetSession()
                            let idleDur = self.idleEnteredAt.map { now - $0 } ?? 0
                            self.todayIdleSecs += idleDur
                            self.idleEnteredAt  = nil
                            auditLog("IDLE_EXIT  idle_duration=\(formatDuration(idleDur))")
                        }

                        if self.sess == nil {
                            self.startSession(activity: activity, ts: now, fresh: true)
                        } else if activity.appName    != self.sess!.appName ||
                                  activity.windowTitle != self.sess!.windowTitle {
                            let switchTS = (prevPoll > 0 && prevPoll > self.sessStart + 1.0) ? prevPoll : now
                            self.db.saveAppSwitch(
                                timestamp:     now,
                                trackingDay:   self.trackingDay,
                                fromApp:       self.sess?.appName,
                                toApp:         activity.appName,
                                timeInFromApp: switchTS - self.sessStart
                            )
                            self.closeSession(endedAt: switchTS)
                            self.startSession(activity: activity, ts: switchTS, fresh: false)
                        } else {
                            if let newURL = activity.url, newURL != self.sess?.url {
                                self.sess?.url    = newURL
                                self.sess?.domain = activity.domain
                            }
                        }
                    }

                    let total = self.computeTotalSeconds(now: now)
                    self.onRefresh?(userIdle ? nil : activity, total, userIdle)
                }

                // Notifications are checked outside the state lock.
                self.stateQueue.sync {
                    if !self.isIdle && !self.paused {
                        self.maybeNotify()
                    }
                }
            }
        }
    }

    // MARK: - Snapshot (every 60 s)

    func snapshot() {
        guard stateQueue.sync(execute: { !paused && !isIdle }) else { return }

        // Battery is refreshed asynchronously by refreshBattery() — read the
        // cached value here so snapshot() never blocks on Process.waitUntilExit().
        let battery = cachedBattery

        stateQueue.sync {
            guard !paused && !isIdle else { return }

            let now = Date().timeIntervalSince1970
            lastBattery = battery

            let snap  = inputMonitor.getCounters()
            let delta = snap.delta(from: snapCtrBase)
            snapCtrBase = snap

            let act = sess

            db.saveSnapshot(
                timestamp:           now,
                trackingDay:         trackingDay,
                appName:             act?.appName,
                windowTitle:         act?.windowTitle,
                url:                 act?.url,
                domain:              act?.domain,
                category:            act?.category,
                idleSeconds:         getIdleSeconds(),
                keystrokesDelta:     delta.keystrokes,
                mouseClicksDelta:    delta.clicks,
                mouseDistanceDelta:  delta.mouseDistPx,
                scrollEventsDelta:   delta.scrollEvents,
                battery:             lastBattery,
                tabCount:            act?.tabCount
            )

            // Time-accuracy audit — scoped to sessions since this tracker instance started.
            let stats       = db.getDayAuditStats(trackingDay: trackingDay, since: auditStartTS)
            let dbActive    = stats.totalDuration
            let currentSeg  = sessStart > 0 ? now - sessStart : 0.0
            let totalActive = dbActive + currentSeg
            let currentIdle = idleEnteredAt.map { now - $0 } ?? 0.0
            let totalIdle   = todayIdleSecs + currentIdle

            // Use auditStartTS as the span floor so gaps before this run don't inflate discrepancy.
            let spanStart = stats.firstStart.map { min($0, auditStartTS) } ?? auditStartTS
            if spanStart > 0 {
                let span        = now - spanStart
                let discrepancy = span - totalActive - totalIdle
                let flag        = abs(discrepancy) < 120 ? "OK" : "<- gap (\(formatDuration(abs(discrepancy))) unaccounted)"
                auditLog(
                    "AUDIT  active=\(formatDuration(totalActive))" +
                    "  idle=\(formatDuration(totalIdle))" +
                    "  span=\(formatDuration(span))" +
                    "  discrepancy=\(formatDuration(abs(discrepancy)))  \(flag)"
                )
            }
        }
    }

    // MARK: - Countdown tick (every 1 s)

    func countdownTick() {
        stateQueue.sync {
            guard workLimit != nil, !isIdle, !paused else {
                limitBlinkOn = true
                return
            }
            if let limit = workLimit, limit.remaining <= 0 {
                limitBlinkOn = !limitBlinkOn
            }
        }
        // Notify status bar to redraw the limit title.
        let total = stateQueue.sync { computeTotalSeconds(now: Date().timeIntervalSince1970) }
        stateQueue.sync {
            onRefresh?(sess, total, isIdle)
        }
    }

    // MARK: - Session lifecycle

    private func startSession(activity: Activity, ts: Double, fresh: Bool) {
        sess          = activity
        sessStart     = ts
        sessCtrBase   = inputMonitor.getCounters()

        if fresh {
            // Recompute the tracking day from the DB after returning from idle
            // or on first startup.
            let last = db.getLastSession()
            let td   = getTrackingDay(lastActivityTS: last?.endedAt, lastTrackingDay: last?.trackingDay)
            if td != trackingDay {
                trackingDay      = td
                milestoneSent    = []
                todayIdleSecs    = 0
            }
        }
        // For app switches (fresh=false): trackingDay is already correct.
    }

    private func resetSession() {
        sess        = nil
        sessStart   = 0
        sessCtrBase = InputCounters()
    }

    private func closeSession(endedAt: Double) {
        guard let s = sess else { return }
        let snap  = inputMonitor.getCounters()
        let delta = snap.delta(from: sessCtrBase)

        db.saveSession(
            appName:       s.appName,
            bundleID:      s.bundleID,
            category:      s.category,
            windowTitle:   s.windowTitle,
            url:           s.url,
            domain:        s.domain,
            startedAt:     sessStart,
            endedAt:       endedAt,
            trackingDay:   trackingDay,
            isIdle:        false,
            isMeeting:     s.isMeeting,
            keystrokes:    delta.keystrokes,
            mouseClicks:   delta.clicks,
            mouseDistance: delta.mouseDistPx,
            scrollEvents:  delta.scrollEvents,
            battery:       lastBattery,
            tabCount:      s.tabCount
        )
    }

    // MARK: - Sleep / wake

    private func handleSleep() {
        stateQueue.sync {
            let now = Date().timeIntervalSince1970
            closeSession(endedAt: now)
            resetSession()
            sleptAt = now
            if isIdle, let entered = idleEnteredAt {
                todayIdleSecs += now - entered
                idleEnteredAt  = nil
            }
        }
        auditLog("SLEEP")
    }

    private func handleWake() {
        stateQueue.sync {
            // Close any session that leaked through the sleep/wake race:
            // the poll timer can fire between handleSleep releasing stateQueue
            // and the OS actually suspending the process, opening a new session
            // that then spans the entire sleep period.
            if sess != nil {
                closeSession(endedAt: sleptAt)
            }
            resetSession()
            sleptAt       = 0
            isIdle        = false
            idleEnteredAt = nil
        }
        auditLog("WAKE")
    }

    // MARK: - Pause / resume

    func togglePause() {
        stateQueue.sync {
            let now = Date().timeIntervalSince1970
            if paused {
                paused = false
                resetSession()
            } else {
                closeSession(endedAt: now)
                resetSession()
                paused = true
            }
        }
    }

    var isPaused: Bool { stateQueue.sync { paused } }

    // MARK: - Work limit

    func setWorkLimit(minutes: Int) {
        stateQueue.sync {
            workLimit = WorkLimit(totalSeconds: Double(minutes) * 60,
                                  startedAt: Date())
        }
    }

    func clearWorkLimit() {
        stateQueue.sync {
            workLimit    = nil
            limitBlinkOn = true
        }
    }

    /// Current work-limit draw state (for status bar rendering).
    func workLimitSnapshot() -> (limit: WorkLimit?, blinkOn: Bool) {
        stateQueue.sync { (workLimit, limitBlinkOn) }
    }

    /// Check milestone sounds for the work limit. Call on stateQueue.
    func checkLimitSounds() {
        guard var limit = workLimit else { return }

        // milestone unit = 5% increments; 16=80%, 20=100%, 21=105%, ...
        let milestone = Int(limit.pct * 20)
        if milestone >= 16 && !limit.milestonesSent.contains(milestone) {
            limit.milestonesSent.insert(milestone)
            workLimit = limit
            if Settings.shared.milestoneSoundsEnabled {
                DispatchQueue.main.async {
                    if milestone == 20 {
                        NSSound(named: "Sosumi")?.play()
                    } else if milestone > 20 {
                        NSSound(named: "Basso")?.play()
                    } else {
                        NSSound(named: "Blow")?.play()
                    }
                }
            }
            if milestone == 20 {
                var l = workLimit!
                l.expired = true
                workLimit = l
            }
        }

        // Catch expiry even if poll timing skipped milestone 20
        if let l = workLimit, l.remaining <= 0, !l.expired {
            var updated = l
            updated.expired = true
            workLimit = updated
        }
    }

    // MARK: - Quit

    func quit() {
        stateQueue.sync {
            if !paused && !isIdle && sess != nil {
                closeSession(endedAt: Date().timeIntervalSince1970)
            }
        }
    }

    // MARK: - Background refresh (audio + battery)

    private func startBackgroundRefreshes() {
        scheduleAudioRefresh(after: 0)
        scheduleBatteryRefresh(after: 0)
    }

    private func scheduleAudioRefresh(after delay: Double) {
        audioRefreshQ.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            let active = isAudioPlaying()
            self.audioLock.lock()
            self._audioActive = active
            self.audioLock.unlock()
            self.scheduleAudioRefresh(after: 2)
        }
    }

    private func scheduleBatteryRefresh(after delay: Double) {
        batteryRefreshQ.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            let info = getBatteryInfo()
            self.batteryLock.lock()
            self._cachedBattery = info
            self.batteryLock.unlock()
            self.scheduleBatteryRefresh(after: 60)
        }
    }

    // MARK: - Helpers

    /// Compute total seconds worked today including the ongoing session.
    /// Must be called on stateQueue.
    private func computeTotalSeconds(now: Double) -> Double {
        let dbTotal    = db.getTodayTotalSeconds(trackingDay: trackingDay)
        let currentSeg = sessStart > 0 ? now - sessStart : 0.0
        return dbTotal + currentSeg
    }

    private func maybeNotify() {
        let now   = Date().timeIntervalSince1970
        let total = computeTotalSeconds(now: now)

        if Settings.shared.notificationsEnabled {
            // Periodic summary (rate-limited to user-configured interval).
            let intervalSecs = Double(Settings.shared.notificationIntervalMinutes) * 60
            if now - lastNotifTS >= intervalSecs {
                let top = db.getTodayTopApp(trackingDay: trackingDay) ?? sess?.appName ?? "your Mac"
                sendNotification(title: "ttracker", message: "\(top) — \(formatDuration(total)) tracked today")
                lastNotifTS = now
            }

            // Hourly milestones.
            for milestone in 1...max(1, Int(total / 3600) + 1) {
                if milestone <= Int(total / 3600) && !milestoneSent.contains(milestone) {
                    milestoneSent.insert(milestone)
                    sendNotification(title: "ttracker", message: "\(milestone)h tracked today")
                }
            }
        }

        // Limit milestone sounds.
        checkLimitSounds()
    }

    private func isTerminalFrontmost() -> Bool {
        guard let name = NSWorkspace.shared.frontmostApplication?.localizedName else { return false }
        return TERMINAL_APPS.contains(name)
    }

    // MARK: Public accessors (safe to call from any thread)

    var currentTrackingDay: String { stateQueue.sync { trackingDay } }
    var currentActivity:    Activity?   { stateQueue.sync { sess } }
    var currentIsIdle:      Bool        { stateQueue.sync { isIdle } }
}

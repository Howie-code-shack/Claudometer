import SwiftUI
import AppKit

// MARK: - Usage view-model
//
// The single observable source of truth for the UI and the menu-bar icon.
// Orchestrates the API client, settings, notifications, login item and Keychain;
// it does not do networking, parsing or persistence itself. @MainActor because
// every @Published mutation must land on the main thread.
@MainActor
final class UsageManager: ObservableObject {
    // Live usage (utilization is already a percentage, 0–100).
    @Published var sessionUsage: Int = 0
    @Published var weeklyUsage: Int = 0
    @Published var weeklySonnetUsage: Int = 0
    @Published var sessionResetsAt: Date?
    @Published var weeklyResetsAt: Date?
    @Published var weeklySonnetResetsAt: Date?
    @Published var lastUpdated: Date = Date()
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var hasWeeklySonnet: Bool = false
    @Published var hasFetchedData: Bool = false
    @Published var needsReauth: Bool = false

    // Progress-bar fractions (0.0–1.0).
    @Published var sessionPercentage: Double = 0.0
    @Published var weeklyPercentage: Double = 0.0
    @Published var weeklySonnetPercentage: Double = 0.0

    // Settings (loaded from / persisted to SettingsStore).
    @Published var usageNotificationsEnabled: Bool
    @Published var openAtLogin: Bool
    @Published var shortcutEnabled: Bool
    @Published var refreshIntervalMinutes: Int
    @Published var notificationThresholds: [Int]
    @Published var menuBarMetric: MenuBarMetric

    private let api = ClaudeAPIClient()
    private weak var delegate: AppDelegate?
    private var sessionCookie: String = ""
    private var lastNotifiedThreshold: Int

    init(delegate: AppDelegate? = nil) {
        self.delegate = delegate

        SettingsStore.migrate()
        usageNotificationsEnabled = SettingsStore.usageNotificationsEnabled
        shortcutEnabled = SettingsStore.shortcutEnabled
        refreshIntervalMinutes = SettingsStore.refreshIntervalMinutes
        notificationThresholds = SettingsStore.notificationThresholds
        menuBarMetric = SettingsStore.menuBarMetric
        lastNotifiedThreshold = SettingsStore.lastNotifiedThreshold
        // Source of truth for launch-at-login is the system, not a cached flag.
        openAtLogin = LoginItem.isEnabled

        loadSessionCookie()
        loadCachedSnapshot()
    }

    var hasCookie: Bool { !sessionCookie.isEmpty }

    // MARK: Cookie

    private func loadSessionCookie() {
        if let saved = CookieStore.load() {
            sessionCookie = saved
            return
        }
        // One-time migration of any legacy plaintext cookie into the Keychain.
        if let legacy = SettingsStore.migrateLegacyCookie() {
            sessionCookie = legacy
        }
    }

    func saveSessionCookie(_ cookie: String) {
        sessionCookie = cookie
        CookieStore.save(cookie)
        needsReauth = false
    }

    func clearSessionCookie() {
        sessionCookie = ""
        CookieStore.delete()
        needsReauth = false

        // Reset all data.
        sessionUsage = 0
        weeklyUsage = 0
        weeklySonnetUsage = 0
        sessionResetsAt = nil
        weeklyResetsAt = nil
        weeklySonnetResetsAt = nil
        hasFetchedData = false
        hasWeeklySonnet = false
        errorMessage = nil
        lastNotifiedThreshold = 0
        SettingsStore.lastNotifiedThreshold = 0
        SettingsStore.clearSnapshot()
        updatePercentages()

        updateStatusBar()
    }

    // MARK: Cached snapshot (instant render on launch)

    private func loadCachedSnapshot() {
        guard let snap = SettingsStore.loadSnapshot() else { return }
        sessionUsage = snap.sessionUsage
        weeklyUsage = snap.weeklyUsage
        weeklySonnetUsage = snap.weeklySonnetUsage
        hasWeeklySonnet = snap.hasWeeklySonnet
        sessionResetsAt = snap.sessionResetsAt
        weeklyResetsAt = snap.weeklyResetsAt
        weeklySonnetResetsAt = snap.weeklySonnetResetsAt
        lastUpdated = snap.lastUpdated
        hasFetchedData = true
        updatePercentages()
    }

    private func persistSnapshot() {
        SettingsStore.saveSnapshot(UsageSnapshot(
            sessionUsage: sessionUsage,
            weeklyUsage: weeklyUsage,
            weeklySonnetUsage: weeklySonnetUsage,
            hasWeeklySonnet: hasWeeklySonnet,
            sessionResetsAt: sessionResetsAt,
            weeklyResetsAt: weeklyResetsAt,
            weeklySonnetResetsAt: weeklySonnetResetsAt,
            lastUpdated: lastUpdated
        ))
    }

    // MARK: Fetch

    func fetchUsage() {
        guard hasCookie else {
            // No cookie yet — the welcome / "Sign in to Claude" UI covers this,
            // so don't surface a scary error in the empty state.
            errorMessage = nil
            updateStatusBar()
            return
        }

        isLoading = true
        errorMessage = nil

        let cookie = sessionCookie
        Task {
            let result = await api.fetchUsage(cookie: cookie)
            isLoading = false
            switch result {
            case .success(let parsed):
                apply(parsed)
            case .failure(let error):
                handle(error)
            }
            updateStatusBar()
        }
    }

    private func apply(_ parsed: ParsedUsage) {
        if let s = parsed.session {
            sessionUsage = s.utilization
            sessionResetsAt = s.resetsAt
        }
        if let w = parsed.weekly {
            weeklyUsage = w.utilization
            weeklyResetsAt = w.resetsAt
        }
        if let sonnet = parsed.weeklySonnet {
            hasWeeklySonnet = true
            weeklySonnetUsage = sonnet.utilization
            weeklySonnetResetsAt = sonnet.resetsAt
        } else {
            hasWeeklySonnet = false
        }

        lastUpdated = Date()
        errorMessage = nil
        needsReauth = false
        hasFetchedData = true
        updatePercentages()
        persistSnapshot()
    }

    private func handle(_ error: APIError) {
        errorMessage = error.userMessage
        switch error {
        case .authExpired:
            needsReauth = true
        case .offline:
            // Keep showing the cached snapshot; the message explains the staleness.
            break
        default:
            break
        }
    }

    // MARK: Percentages + status bar

    func updatePercentages() {
        sessionPercentage = Double(sessionUsage) / 100.0
        weeklyPercentage = Double(weeklyUsage) / 100.0
        weeklySonnetPercentage = Double(weeklySonnetUsage) / 100.0
    }

    /// Highest utilization across all active windows.
    var highestUtilization: Int {
        max(sessionUsage, weeklyUsage, hasWeeklySonnet ? weeklySonnetUsage : 0)
    }

    /// The number shown in the menu bar, per the user's chosen metric.
    /// nil when there's no data to show (renders as a neutral dash).
    func menuBarPercentage() -> Int? {
        guard hasFetchedData else { return nil }
        switch menuBarMetric {
        case .session: return sessionUsage
        case .weekly:  return weeklyUsage
        case .highest: return highestUtilization
        }
    }

    func updateStatusBar() {
        delegate?.updateStatusIcon(percentage: menuBarPercentage())
        // Threshold alerts track whichever window the user chose for the menu bar.
        checkNotificationThresholds()
    }

    /// Seconds until the next scheduled refresh. Near a limit we poll more often,
    /// which intentionally overrides the user's configured interval.
    func nextRefreshSeconds() -> TimeInterval {
        let base = TimeInterval(refreshIntervalMinutes * 60)
        if hasFetchedData && highestUtilization >= 80 {
            return min(base, 60)
        }
        return base
    }

    // MARK: Notifications

    /// The usage window that drives notifications — kept in sync with the
    /// menu-bar metric so alerts fire for the limit the user is actually watching
    /// (e.g. someone tracking their weekly limit gets weekly alerts, not session).
    /// Returns the current percentage and a label for the alert body.
    private func notificationTarget() -> (percentage: Int, label: String) {
        switch menuBarMetric {
        case .session:
            return (sessionUsage, "5-hour session")
        case .weekly:
            return (weeklyUsage, "weekly (7-day)")
        case .highest:
            // Report whichever window is actually the highest right now.
            var candidates: [(Int, String)] = [
                (sessionUsage, "5-hour session"),
                (weeklyUsage, "weekly (7-day)"),
            ]
            if hasWeeklySonnet {
                candidates.append((weeklySonnetUsage, "weekly Sonnet (7-day)"))
            }
            return candidates.max(by: { $0.0 < $1.0 }) ?? (0, "usage")
        }
    }

    private func checkNotificationThresholds() {
        guard usageNotificationsEnabled else { return }

        let target = notificationTarget()
        let percentage = target.percentage
        let thresholds = notificationThresholds

        // Fire only the single highest newly-crossed threshold this tick. Looping
        // and notifying per crossed threshold would emit a burst of banners (e.g.
        // jumping from 0% to 80% with thresholds [25,50,75] sent three at once).
        if let crossed = thresholds.filter({ percentage >= $0 && $0 > lastNotifiedThreshold }).max() {
            sendNotification(percentage: percentage, windowLabel: target.label)
            lastNotifiedThreshold = crossed
            SettingsStore.lastNotifiedThreshold = crossed
        }

        // Reset once usage drops back below the last-notified threshold.
        if percentage < lastNotifiedThreshold {
            let newThreshold = thresholds.filter { $0 <= percentage }.last ?? 0
            lastNotifiedThreshold = newThreshold
            SettingsStore.lastNotifiedThreshold = newThreshold
        }
    }

    private func sendNotification(percentage: Int, windowLabel: String) {
        NotificationService.send(
            title: "Claude Usage Alert",
            body: "You've reached \(percentage)% of your \(windowLabel) limit"
        )
    }

    func sendTestNotification() {
        let label = notificationTarget().label
        NotificationService.send(
            title: "Claude Usage Alert",
            body: "Test notification — You've reached 75% of your \(label) limit"
        )
    }

    // MARK: Settings mutations (with side effects)

    func setNotificationsEnabled(_ enabled: Bool) {
        usageNotificationsEnabled = enabled
        SettingsStore.usageNotificationsEnabled = enabled
    }

    /// Returns an error message to show if the system rejected the change.
    @discardableResult
    func setOpenAtLogin(_ enabled: Bool) -> String? {
        do {
            try LoginItem.setEnabled(enabled)
            openAtLogin = LoginItem.isEnabled   // reflect actual system state
            return nil
        } catch {
            openAtLogin = LoginItem.isEnabled   // revert toggle to reality
            return "Couldn't update Login Items: \(error.localizedDescription)"
        }
    }

    func setShortcutEnabled(_ enabled: Bool) {
        shortcutEnabled = enabled
        SettingsStore.shortcutEnabled = enabled
        delegate?.setShortcutEnabled(enabled)
    }

    func setRefreshInterval(_ minutes: Int) {
        refreshIntervalMinutes = minutes
        SettingsStore.refreshIntervalMinutes = minutes
        delegate?.rescheduleFetch()
    }

    func toggleThreshold(_ threshold: Int) {
        var set = Set(notificationThresholds)
        if set.contains(threshold) {
            set.remove(threshold)
        } else {
            set.insert(threshold)
        }
        notificationThresholds = set.sorted()
        SettingsStore.notificationThresholds = notificationThresholds
    }

    func setMenuBarMetric(_ metric: MenuBarMetric) {
        menuBarMetric = metric
        SettingsStore.menuBarMetric = metric
        updateStatusBar()
    }
}

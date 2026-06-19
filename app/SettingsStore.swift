import Foundation

/// Which usage window drives the menu-bar percentage + icon color.
enum MenuBarMetric: String, CaseIterable, Identifiable {
    case session   // 5-hour
    case weekly    // 7-day
    case highest   // worst of all windows

    var id: String { rawValue }
    var label: String {
        switch self {
        case .session: return "Session (5h)"
        case .weekly:  return "Weekly (7d)"
        case .highest: return "Highest"
        }
    }
}

// MARK: - Settings persistence (UserDefaults)
//
// Single home for everything we persist to UserDefaults, including the one-time
// migrations from older key layouts. Typed accessors keep the rest of the app
// from touching raw UserDefaults keys.
enum SettingsStore {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let usageNotificationsEnabled = "usage_notifications_enabled"
        static let legacyNotificationsEnabled = "notifications_enabled"   // pre-v1.1
        static let openAtLogin = "open_at_login"
        static let shortcutEnabled = "shortcut_enabled"
        static let lastNotifiedThreshold = "last_notified_threshold"
        static let refreshIntervalMinutes = "refresh_interval_minutes"
        static let notificationThresholds = "notification_thresholds"
        static let menuBarMetric = "menu_bar_metric"
        static let usageSnapshot = "usage_snapshot"
        static let legacyCookie = "claude_session_cookie"   // plaintext, pre-Keychain
    }

    /// Sensible defaults applied when a key has never been written.
    static let defaultThresholds = [25, 50, 75, 90]
    static let defaultRefreshMinutes = 5

    // MARK: One-time migrations

    /// Run once at launch, before any value is read.
    static func migrate() {
        // Migrate the legacy single notifications_enabled flag (pre-v1.1).
        if defaults.object(forKey: Key.usageNotificationsEnabled) == nil {
            let legacyHasKey = defaults.object(forKey: Key.legacyNotificationsEnabled) != nil
            let value = legacyHasKey ? defaults.bool(forKey: Key.legacyNotificationsEnabled) : true
            defaults.set(value, forKey: Key.usageNotificationsEnabled)
        }
    }

    /// Move any legacy plaintext cookie from UserDefaults into the Keychain,
    /// returning it so the caller can adopt it. Scrubs the old copy.
    static func migrateLegacyCookie() -> String? {
        guard let legacy = defaults.string(forKey: Key.legacyCookie), !legacy.isEmpty else {
            return nil
        }
        CookieStore.save(legacy)
        defaults.removeObject(forKey: Key.legacyCookie)
        return legacy
    }

    // MARK: Typed accessors

    static var usageNotificationsEnabled: Bool {
        get {
            defaults.object(forKey: Key.usageNotificationsEnabled) == nil
                ? true
                : defaults.bool(forKey: Key.usageNotificationsEnabled)
        }
        set { defaults.set(newValue, forKey: Key.usageNotificationsEnabled) }
    }

    static var shortcutEnabled: Bool {
        get {
            defaults.object(forKey: Key.shortcutEnabled) == nil
                ? true   // default enabled
                : defaults.bool(forKey: Key.shortcutEnabled)
        }
        set { defaults.set(newValue, forKey: Key.shortcutEnabled) }
    }

    static var lastNotifiedThreshold: Int {
        get { defaults.integer(forKey: Key.lastNotifiedThreshold) }
        set { defaults.set(newValue, forKey: Key.lastNotifiedThreshold) }
    }

    static var refreshIntervalMinutes: Int {
        get {
            let v = defaults.integer(forKey: Key.refreshIntervalMinutes)
            return v > 0 ? v : defaultRefreshMinutes
        }
        set { defaults.set(newValue, forKey: Key.refreshIntervalMinutes) }
    }

    static var notificationThresholds: [Int] {
        get {
            guard let arr = defaults.array(forKey: Key.notificationThresholds) as? [Int],
                  !arr.isEmpty else { return defaultThresholds }
            return arr.sorted()
        }
        set { defaults.set(newValue.sorted(), forKey: Key.notificationThresholds) }
    }

    static var menuBarMetric: MenuBarMetric {
        get { MenuBarMetric(rawValue: defaults.string(forKey: Key.menuBarMetric) ?? "") ?? .session }
        set { defaults.set(newValue.rawValue, forKey: Key.menuBarMetric) }
    }

    // MARK: Cached usage snapshot (for instant render on launch)

    static func loadSnapshot() -> UsageSnapshot? {
        guard let data = defaults.data(forKey: Key.usageSnapshot) else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }

    static func saveSnapshot(_ snapshot: UsageSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Key.usageSnapshot)
    }

    static func clearSnapshot() {
        defaults.removeObject(forKey: Key.usageSnapshot)
    }
}

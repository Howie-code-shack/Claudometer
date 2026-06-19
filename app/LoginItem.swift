import Foundation
import ServiceManagement

// MARK: - Launch at login (SMAppService)
//
// Wraps SMAppService.mainApp, the modern (macOS 13+) login-item API. The whole
// app targets macOS 13+, so no availability fallback is needed. NOTE: register()
// only takes effect for a properly signed, Launch-Services-registered bundle —
// so `isEnabled` reads back the *actual* system status rather than a cached
// boolean, which is what makes this a real toggle and not a no-op flag.
enum LoginItem {
    /// True when the app is registered to launch at login, per the system.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Register or unregister the app as a login item. Throws if the system
    /// rejects the change (e.g. an unsigned bundle); callers should surface that.
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        }
    }
}

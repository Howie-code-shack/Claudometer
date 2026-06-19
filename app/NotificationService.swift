import Foundation
import UserNotifications

// MARK: - User notifications (UserNotifications framework)
//
// Replaces the long-deprecated NSUserNotification. UNUserNotificationCenter
// requires (1) a bundled, signed app and (2) an explicit authorization grant —
// without either, delivery silently no-ops, so we request authorization once at
// launch and only attempt delivery after that.
enum NotificationService {
    // UNUserNotificationCenter suppresses banners while the posting app is
    // frontmost/active — and Claudometer becomes active whenever you open its
    // popover (which is exactly when the Test Notification button fires). Without
    // a delegate that opts into foreground presentation, those alerts silently
    // never appear. NSUserNotification didn't have this behavior, which is why
    // notifications "stopped working" after the migration.
    private final class Delegate: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    willPresent notification: UNNotification,
                                    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
            completionHandler([.banner, .list, .sound])
        }
    }

    private static let delegate = Delegate()

    /// Ask the user for permission to post alerts, and install the delegate so
    /// alerts present even when Claudometer is the active app. Safe to call
    /// repeatedly; the system only prompts the first time.
    static func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Deliver a notification immediately. Honors the system authorization state
    /// (a denied user simply sees nothing).
    static func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // nil trigger => deliver right away.
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}

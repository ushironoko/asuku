import AppKit
import AsukuShared
import Foundation
import UserNotifications

/// Category identifiers for notification actions
enum NotificationCategory {
    static let permissionRequest = "PERMISSION_REQUEST"
    static let agentNotification = "AGENT_NOTIFICATION"
}

/// Action identifiers
enum NotificationAction {
    static let allow = "ALLOW"
    static let deny = "DENY"
}

/// Manages macOS user notifications
final class NotificationManager: NSObject, @unchecked Sendable,
    UNUserNotificationCenterDelegate
{
    /// Called when user taps Allow/Deny on a permission request notification
    var onPermissionResponse: (@Sendable (String, PermissionDecision) -> Void)?

    private let center = UNUserNotificationCenter.current()
    private var notificationPermissionGranted = false

    override init() {
        super.init()
        center.delegate = self
        registerCategories()
    }

    /// Request notification permission from the user
    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(
                options: [.alert, .sound, .badge])
            notificationPermissionGranted = granted
            return granted
        } catch {
            print("[NotificationManager] Permission request failed: \(error)")
            return false
        }
    }

    /// Check current notification settings
    func checkPermission() async -> Bool {
        let settings = await center.notificationSettings()
        let granted = settings.authorizationStatus == .authorized
        notificationPermissionGranted = granted
        return granted
    }

    /// Show a permission request notification with Allow/Deny actions
    func showPermissionRequest(_ request: PendingRequest) async {
        let content = UNMutableNotificationContent()
        content.title = "Permission Request: \(request.event.toolName)"
        content.body = request.notificationBody
        content.categoryIdentifier = NotificationCategory.permissionRequest
        content.userInfo = ["requestId": request.id]
        content.sound = .default
        // Thread by session for grouping
        content.threadIdentifier = request.event.sessionId

        let triggerRequest = UNNotificationRequest(
            identifier: request.id,
            content: content,
            trigger: nil  // Deliver immediately
        )

        do {
            try await center.add(triggerRequest)
        } catch {
            print("[NotificationManager] Failed to show notification: \(error)")
            // Fallback: play sound
            playFallbackSound()
        }
    }

    /// Show a generic notification (no actions)
    func showNotification(title: String, body: String, sessionId: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = InputSanitizer.sanitizeForNotification(body)
        content.categoryIdentifier = NotificationCategory.agentNotification
        content.sound = .default
        content.threadIdentifier = sessionId

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
        } catch {
            print("[NotificationManager] Failed to show notification: \(error)")
        }
    }

    /// Remove a delivered notification by its identifier
    func removeNotification(identifier: String) {
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    // MARK: - Private

    private func registerCategories() {
        let allowAction = UNNotificationAction(
            identifier: NotificationAction.allow,
            title: "Allow",
            options: []
        )

        let denyAction = UNNotificationAction(
            identifier: NotificationAction.deny,
            title: "Deny",
            options: [.destructive]
        )

        let permissionCategory = UNNotificationCategory(
            identifier: NotificationCategory.permissionRequest,
            actions: [allowAction, denyAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let notificationCategory = UNNotificationCategory(
            identifier: NotificationCategory.agentNotification,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([permissionCategory, notificationCategory])
    }

    private func playFallbackSound() {
        NSSound.beep()
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Handle notification action responses (Allow/Deny buttons)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let requestId = response.notification.request.content.userInfo["requestId"] as? String

        guard let requestId else {
            completionHandler()
            return
        }

        let decision: PermissionDecision
        switch response.actionIdentifier {
        case NotificationAction.allow:
            decision = .allow
        case NotificationAction.deny:
            decision = .deny
        case UNNotificationDismissActionIdentifier:
            // Dismiss without action — treat as deny for safety
            decision = .deny
        default:
            // Default tap (no specific action) — treat as allow for quick response
            decision = .allow
            completionHandler()
            return
        }

        onPermissionResponse?(requestId, decision)
        completionHandler()
    }

    /// Show notifications even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) ->
            Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}

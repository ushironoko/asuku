import AsukuShared
import Foundation

/// Claude Code Notification hook input (stdin JSON)
struct NotificationInput: Codable {
    let session_id: String
    let hook_event_name: String
    let notification_type: String?
    let message: String?
    let title: String?
}

enum NotificationHandler {
    static func handle(inputData: Data) throws {
        let decoder = JSONDecoder()
        let input = try decoder.decode(NotificationInput.self, from: inputData)

        let event = NotificationEvent(
            sessionId: input.session_id,
            title: input.title ?? "Claude Code",
            body: input.message ?? input.notification_type ?? "Notification"
        )

        let message = IPCMessage(payload: .notification(event))

        // Fire-and-forget: send notification and exit immediately
        try IPCClient.sendOnly(message)
    }
}

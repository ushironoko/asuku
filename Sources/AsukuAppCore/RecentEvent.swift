import AsukuShared
import Foundation

/// Recent event for history display.
/// Kind enum makes the 3 valid states explicit — no more Bool + Optional combinations.
public struct RecentEvent: Identifiable, Sendable {
    public enum Kind: Sendable, Equatable {
        case permissionResponse(PermissionDecision)
        case notification
        case timeout
    }

    public let id: String
    public let toolName: String
    public let kind: Kind
    public let timestamp: Date
    public let sessionId: String

    public init(
        id: String,
        toolName: String,
        kind: Kind,
        timestamp: Date,
        sessionId: String
    ) {
        self.id = id
        self.toolName = toolName
        self.kind = kind
        self.timestamp = timestamp
        self.sessionId = sessionId
    }

    public var displayText: String {
        switch kind {
        case .notification:
            return toolName
        case .permissionResponse(let decision):
            return "\(toolName) — \(decision == .allow ? "Allowed" : "Denied")"
        case .timeout:
            return "\(toolName) — Timed Out"
        }
    }

    public var timeText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

import AsukuShared
import Foundation

/// Represents a pending permission request awaiting user response
public struct PendingRequest: Identifiable, Sendable {
    public let id: String  // requestId
    public let event: PermissionRequestEvent
    public let responder: any IPCResponding
    public let createdAt: Date
    public var timeoutSeconds: TimeInterval?

    public init(
        id: String,
        event: PermissionRequestEvent,
        responder: any IPCResponding,
        createdAt: Date,
        timeoutSeconds: TimeInterval?
    ) {
        self.id = id
        self.event = event
        self.responder = responder
        self.createdAt = createdAt
        self.timeoutSeconds = timeoutSeconds
    }

    public var isExpired: Bool {
        guard let timeoutSeconds else { return false }
        return Date().timeIntervalSince(createdAt) >= timeoutSeconds
    }

    /// Summary text for UI display
    public var displayTitle: String {
        switch event.toolName {
        case "Bash":
            if let command = event.toolInput["command"]?.stringValue {
                return "Bash: \(InputSanitizer.sanitizeForNotification(command, maxLength: 80))"
            }
            return "Bash command"
        case "Write", "Edit":
            if let filePath = event.toolInput["file_path"]?.stringValue {
                return "\(event.toolName): \(filePath)"
            }
            return event.toolName
        default:
            return event.toolName
        }
    }

    /// Notification body text
    public var notificationBody: String {
        switch event.toolName {
        case "Bash":
            if let command = event.toolInput["command"]?.stringValue {
                return InputSanitizer.sanitizeForNotification(command)
            }
            return "Execute bash command"
        case "Write":
            if let filePath = event.toolInput["file_path"]?.stringValue {
                return "Write to \(filePath)"
            }
            return "Write file"
        case "Edit":
            if let filePath = event.toolInput["file_path"]?.stringValue {
                return "Edit \(filePath)"
            }
            return "Edit file"
        default:
            let inputDesc = event.toolInput.map { "\($0.key): \($0.value)" }.joined(
                separator: ", ")
            return InputSanitizer.sanitizeForNotification(
                "\(event.toolName): \(inputDesc)")
        }
    }
}

/// Actor that manages pending permission requests with timeout handling
public actor PendingRequestManager {
    /// Default timeout: 280 seconds (before Claude Code's 300s hook timeout)
    public static let defaultTimeoutSeconds: TimeInterval = 280

    private var requests: [String: PendingRequest] = [:]
    private var timeoutTasks: [String: Task<Void, Never>] = [:]

    /// Called when a request expires (auto-deny)
    public var onTimeout: (@Sendable (String) -> Void)?

    public init() {}

    /// All currently pending requests
    public var pendingRequests: [PendingRequest] {
        Array(requests.values).sorted { $0.createdAt < $1.createdAt }
    }

    /// Number of pending requests
    public var pendingCount: Int {
        requests.count
    }

    /// Registers a new pending request
    public func addRequest(
        event: PermissionRequestEvent,
        responder: any IPCResponding,
        timeoutSeconds: TimeInterval? = defaultTimeoutSeconds
    ) {
        let request = PendingRequest(
            id: event.requestId,
            event: event,
            responder: responder,
            createdAt: Date(),
            timeoutSeconds: timeoutSeconds
        )
        requests[event.requestId] = request

        // Start timeout timer only when timeout is enabled
        if let timeoutSeconds {
            let requestId = event.requestId
            let task = Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                guard !Task.isCancelled else { return }
                await self?.handleTimeout(requestId: requestId)
            }
            timeoutTasks[event.requestId] = task
        }
    }

    /// Resolves a pending request with the user's decision
    public func resolve(requestId: String, decision: PermissionDecision) -> Bool {
        guard let request = requests[requestId] else {
            return false
        }

        // Send response
        let response = IPCResponse(requestId: requestId, decision: decision)
        request.responder.send(response)

        // Cleanup
        cleanup(requestId: requestId)
        return true
    }

    /// Removes a pending request (e.g., on disconnect) without sending a response
    public func remove(requestId: String) {
        cleanup(requestId: requestId)
    }

    /// Gets a specific pending request
    public func getRequest(_ requestId: String) -> PendingRequest? {
        requests[requestId]
    }

    /// Reschedules or cancels timeout tasks for all in-flight requests.
    /// Called when timeout configuration changes.
    public func rescheduleTimeouts(effectiveTimeout: TimeInterval?) {
        // Cancel all existing timeout tasks
        for (_, task) in timeoutTasks {
            task.cancel()
        }
        timeoutTasks.removeAll()

        // Update stored timeout so isExpired stays consistent
        for requestId in requests.keys {
            requests[requestId]?.timeoutSeconds = effectiveTimeout
        }

        guard let effectiveTimeout else { return }

        // Reschedule each pending request with remaining time
        for (requestId, request) in requests {
            let elapsed = Date().timeIntervalSince(request.createdAt)
            let remaining = max(0, effectiveTimeout - elapsed)
            let rid = requestId
            let task = Task { [weak self] in
                if remaining > 0 {
                    try? await Task.sleep(for: .seconds(remaining))
                }
                guard !Task.isCancelled else { return }
                await self?.handleTimeout(requestId: rid)
            }
            timeoutTasks[requestId] = task
        }
    }

    private func handleTimeout(requestId: String) {
        guard requests[requestId] != nil else { return }

        // Auto-deny on timeout
        let _ = resolve(requestId: requestId, decision: .deny)
        onTimeout?(requestId)
    }

    private func cleanup(requestId: String) {
        requests.removeValue(forKey: requestId)
        timeoutTasks[requestId]?.cancel()
        timeoutTasks.removeValue(forKey: requestId)
    }
}

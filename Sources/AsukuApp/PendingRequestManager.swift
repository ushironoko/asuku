import AsukuShared
import Foundation

/// Represents a pending permission request awaiting user response
struct PendingRequest: Identifiable, Sendable {
    let id: String  // requestId
    let event: PermissionRequestEvent
    let responder: IPCResponder
    let createdAt: Date
    let timeoutSeconds: TimeInterval

    var isExpired: Bool {
        Date().timeIntervalSince(createdAt) >= timeoutSeconds
    }

    /// Summary text for UI display
    var displayTitle: String {
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
    var notificationBody: String {
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
actor PendingRequestManager {
    /// Default timeout: 280 seconds (before Claude Code's 300s hook timeout)
    static let defaultTimeoutSeconds: TimeInterval = 280

    private var requests: [String: PendingRequest] = [:]
    private var timeoutTasks: [String: Task<Void, Never>] = [:]

    /// Called when a request expires (auto-deny)
    var onTimeout: (@Sendable (String) -> Void)?

    /// All currently pending requests
    var pendingRequests: [PendingRequest] {
        Array(requests.values).sorted { $0.createdAt < $1.createdAt }
    }

    /// Number of pending requests
    var pendingCount: Int {
        requests.count
    }

    /// Registers a new pending request
    func addRequest(
        event: PermissionRequestEvent,
        responder: IPCResponder,
        timeoutSeconds: TimeInterval = defaultTimeoutSeconds
    ) {
        let request = PendingRequest(
            id: event.requestId,
            event: event,
            responder: responder,
            createdAt: Date(),
            timeoutSeconds: timeoutSeconds
        )
        requests[event.requestId] = request

        // Start timeout timer
        let requestId = event.requestId
        let task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeoutSeconds))
            guard !Task.isCancelled else { return }
            await self?.handleTimeout(requestId: requestId)
        }
        timeoutTasks[event.requestId] = task
    }

    /// Resolves a pending request with the user's decision
    func resolve(requestId: String, decision: PermissionDecision) -> Bool {
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
    func remove(requestId: String) {
        cleanup(requestId: requestId)
    }

    /// Gets a specific pending request
    func getRequest(_ requestId: String) -> PendingRequest? {
        requests[requestId]
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

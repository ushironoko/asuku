/// Unified server state for IPC and Webhook servers.
/// Replaces loose `isRunning: Bool` + `error: String?` combinations
/// with a single enum that makes invalid states unrepresentable.
public enum ServerState: Equatable, Sendable {
    case stopped
    case running
    case failed(String)

    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    public var errorMessage: String? {
        if case .failed(let msg) = self { return msg }
        return nil
    }
}

import AsukuShared

/// All actions from View to Coordinator.
/// Adding a new case forces exhaustive switch handling — compiler catches omissions.
public enum AppAction: Sendable, Equatable {
    case resolveRequest(requestId: String, decision: PermissionDecision)
    case ntfyConfigChanged
    case stop
}

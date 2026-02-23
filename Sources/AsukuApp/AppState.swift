import AsukuAppCore
import AsukuShared
import Foundation
import Observation

/// UI-only application state. No service objects, no server management.
/// Orchestration lives in AppCoordinator.
@MainActor
@Observable
final class AppState {
    var pendingRequests: [PendingRequest] = []
    var recentEvents: [RecentEvent] = []
    var ipcServerState: ServerState = .stopped
    var webhookServerState: ServerState = .stopped
    var notificationPermissionGranted = false
    var ntfyConfig: NtfyConfig

    private let maxRecentEvents = 50

    init(ntfyConfig: NtfyConfig = NtfyConfigStore.load()) {
        self.ntfyConfig = ntfyConfig
    }

    func addRecentEvent(toolName: String, kind: RecentEvent.Kind, sessionId: String) {
        let event = RecentEvent(
            id: UUID().uuidString,
            toolName: toolName,
            kind: kind,
            timestamp: Date(),
            sessionId: sessionId
        )
        recentEvents.insert(event, at: 0)
        if recentEvents.count > maxRecentEvents {
            recentEvents = Array(recentEvents.prefix(maxRecentEvents))
        }
    }

    func updateNtfyConfig(_ config: NtfyConfig) {
        ntfyConfig = config
        NtfyConfigStore.save(config)
    }
}

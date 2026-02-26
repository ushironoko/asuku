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

    // Status monitoring
    var activeSessions: [SessionStatus] = []
    var enabledPlugins: [EnabledPlugin] = []
    var sessionHistory: [SessionHistoryEntry] = []

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

    // MARK: - Status Monitoring

    func applyStatusUpdates(_ events: [StatusUpdateEvent], removing staleSessionIds: [String]) {
        // Remove stale sessions that the throttler evicted
        if !staleSessionIds.isEmpty {
            activeSessions.removeAll { staleSessionIds.contains($0.sessionId) }
        }

        // Upsert active sessions
        for event in events {
            if let index = activeSessions.firstIndex(where: { $0.sessionId == event.sessionId }) {
                activeSessions[index].statusline = event.statusline
                activeSessions[index].lastUpdated = event.timestamp
            } else {
                activeSessions.insert(
                    SessionStatus(
                        sessionId: event.sessionId,
                        statusline: event.statusline,
                        lastUpdated: event.timestamp
                    ),
                    at: 0
                )
            }
        }
    }

    func updatePlugins(_ plugins: [EnabledPlugin]) {
        enabledPlugins = plugins
    }

    func updateSessionHistory(_ history: [SessionHistoryEntry]) {
        sessionHistory = history
    }
}

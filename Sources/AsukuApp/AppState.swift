import AsukuShared
import Foundation
import Observation

/// Recent event for history display
struct RecentEvent: Identifiable, Sendable {
    let id = UUID().uuidString
    let toolName: String
    let decision: PermissionDecision?
    let timestamp: Date
    let sessionId: String
    let isNotification: Bool

    var displayText: String {
        if isNotification {
            return "\(toolName)"
        }
        let decisionText = decision.map { $0 == .allow ? "Allowed" : "Denied" } ?? "Pending"
        return "\(toolName) — \(decisionText)"
    }

    var timeText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

/// Main application state, observed by SwiftUI
@MainActor
@Observable
final class AppState {
    var pendingRequests: [PendingRequest] = []
    var recentEvents: [RecentEvent] = []
    var isServerRunning = false
    var notificationPermissionGranted = false
    var isWebhookServerRunning = false
    var webhookServerError: String?

    let pendingManager = PendingRequestManager()
    let notificationManager = NotificationManager()
    let ntfyConfig = NtfyConfig()
    private var ipcServer: IPCServer?
    private var ntfyNotifier: NtfyNotifier?
    private var webhookServer: WebhookServer?

    /// Maximum recent events to keep
    private let maxRecentEvents = 50

    init() {
        // Start IPC server synchronously at init time
        startServer()
        // Setup handlers
        setupNotificationHandler()
        // Setup ntfy integration
        setupNtfy()
        // Request notification permission asynchronously
        Task { @MainActor [weak self] in
            await self?.setupAsync()
        }
    }

    /// Synchronous server startup - called during init
    private func startServer() {
        do {
            let socketPath = try SocketPath.resolve()
            let server = IPCServer(socketPath: socketPath)

            server.onPermissionRequest = { [weak self] event, responder in
                guard let self else { return }
                Task { @MainActor in
                    await self.handlePermissionRequest(event: event, responder: responder)
                }
            }

            server.onNotification = { [weak self] event in
                guard let self else { return }
                Task { @MainActor in
                    await self.handleNotification(event: event)
                }
            }

            server.onDisconnect = { [weak self] requestId in
                guard let self else { return }
                if let requestId {
                    Task { @MainActor in
                        await self.pendingManager.remove(requestId: requestId)
                        await self.refreshPendingRequests()
                    }
                }
            }

            try server.start()
            ipcServer = server
            isServerRunning = true
            print("[AppState] Server started on \(socketPath)")
        } catch {
            print("[AppState] Failed to start server: \(error)")
            isServerRunning = false
        }
    }

    private func setupNotificationHandler() {
        notificationManager.onPermissionResponse = { [weak self] requestId, decision in
            guard let self else { return }
            Task { @MainActor in
                await self.resolveRequest(requestId: requestId, decision: decision)
            }
        }
    }

    /// Async setup - notification permission + pending manager timeout
    private func setupAsync() async {
        notificationPermissionGranted = await notificationManager.requestPermission()
        print("[AppState] Notification permission: \(notificationPermissionGranted)")

        await pendingManager.setOnTimeout { [weak self] requestId in
            guard let self else { return }
            Task { @MainActor in
                self.notificationManager.removeNotification(identifier: requestId)
                await self.refreshPendingRequests()
                self.addRecentEvent(
                    toolName: "Timeout",
                    decision: .deny,
                    sessionId: "",
                    isNotification: false
                )
            }
        }
    }

    func stop() {
        ipcServer?.stop()
        ipcServer = nil
        isServerRunning = false
        stopWebhookServer()
    }

    // MARK: - Ntfy integration

    private func setupNtfy() {
        ntfyNotifier = NtfyNotifier(config: ntfyConfig)
        if ntfyConfig.isEnabled {
            startWebhookServer()
        }
    }

    func ntfyConfigChanged() {
        if ntfyConfig.isEnabled {
            startWebhookServer()
        } else {
            stopWebhookServer()
        }
    }

    private func startWebhookServer() {
        stopWebhookServer()

        let server = WebhookServer(port: ntfyConfig.webhookPort)

        server.onWebhookResponse = { [weak self] requestId, decision in
            guard let self else { return }
            Task { @MainActor in
                await self.resolveRequest(requestId: requestId, decision: decision)
            }
        }

        do {
            try server.start()
            webhookServer = server
            isWebhookServerRunning = true
            webhookServerError = nil
            print("[AppState] Webhook server started on port \(ntfyConfig.webhookPort)")
        } catch {
            print("[AppState] Failed to start webhook server: \(error)")
            isWebhookServerRunning = false
            webhookServerError = error.localizedDescription
        }
    }

    private func stopWebhookServer() {
        webhookServer?.stop()
        webhookServer = nil
        isWebhookServerRunning = false
        webhookServerError = nil
    }

    // MARK: - Request handling

    func resolveRequest(requestId: String, decision: PermissionDecision) async {
        let resolved = await pendingManager.resolve(
            requestId: requestId, decision: decision)
        if resolved {
            notificationManager.removeNotification(identifier: requestId)
            if let request = pendingRequests.first(where: { $0.id == requestId }) {
                addRecentEvent(
                    toolName: request.event.toolName,
                    decision: decision,
                    sessionId: request.event.sessionId,
                    isNotification: false
                )
            }
            await refreshPendingRequests()
        }
    }

    // MARK: - Private

    private func handlePermissionRequest(
        event: PermissionRequestEvent, responder: IPCResponder
    ) async {
        print("[AppState] Received permission request: \(event.toolName) (\(event.requestId))")
        await pendingManager.addRequest(event: event, responder: responder)
        await refreshPendingRequests()

        if let request = await pendingManager.getRequest(event.requestId) {
            await notificationManager.showPermissionRequest(request)
            // ntfy notification (sends only when enabled)
            await ntfyNotifier?.sendPermissionRequest(request)
        }
    }

    private func handleNotification(event: NotificationEvent) async {
        print("[AppState] Received notification: \(event.title)")
        await notificationManager.showNotification(
            title: event.title,
            body: event.body,
            sessionId: event.sessionId
        )
        addRecentEvent(
            toolName: event.title,
            decision: nil,
            sessionId: event.sessionId,
            isNotification: true
        )
    }

    private func refreshPendingRequests() async {
        pendingRequests = await pendingManager.pendingRequests
    }

    private func addRecentEvent(
        toolName: String, decision: PermissionDecision?, sessionId: String,
        isNotification: Bool
    ) {
        let event = RecentEvent(
            toolName: toolName,
            decision: decision,
            timestamp: Date(),
            sessionId: sessionId,
            isNotification: isNotification
        )
        recentEvents.insert(event, at: 0)
        if recentEvents.count > maxRecentEvents {
            recentEvents = Array(recentEvents.prefix(maxRecentEvents))
        }
    }
}

extension PendingRequestManager {
    func setOnTimeout(_ handler: @escaping @Sendable (String) -> Void) {
        onTimeout = handler
    }
}

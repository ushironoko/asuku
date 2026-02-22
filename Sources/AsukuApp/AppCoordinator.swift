import AsukuAppCore
import AsukuShared
import Foundation

/// Orchestrates all service objects and coordinates between them and AppState.
/// Extracted from the former god-object AppState.
@MainActor
final class AppCoordinator {
    let appState: AppState

    private var ipcServer: IPCServer?
    private var webhookServer: WebhookServer?
    private let pendingManager = PendingRequestManager()
    private let notificationManager = NotificationManager()

    init(appState: AppState) {
        self.appState = appState
        startIPCServer()
        setupNotificationHandler()
        if appState.ntfyConfig.isEnabled {
            startWebhookServer()
        }
        Task { @MainActor [weak self] in
            await self?.setupAsync()
        }
    }

    // MARK: - Action dispatch

    func dispatch(_ action: AppAction) {
        switch action {
        case .resolveRequest(let requestId, let decision):
            Task { await resolveRequest(requestId: requestId, decision: decision) }
        case .ntfyConfigChanged:
            ntfyConfigChanged()
        case .stop:
            stop()
        }
    }

    // MARK: - IPC Server

    private func startIPCServer() {
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

            server.onStateChange = { [weak self] state in
                guard let self else { return }
                Task { @MainActor in
                    self.appState.ipcServerState = state
                }
            }

            try server.start()
            ipcServer = server
            print("[AppCoordinator] Server started on \(socketPath)")
        } catch {
            print("[AppCoordinator] Failed to start server: \(error)")
            appState.ipcServerState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Notification handler

    private func setupNotificationHandler() {
        notificationManager.onPermissionResponse = { [weak self] requestId, decision in
            guard let self else { return }
            Task { @MainActor in
                await self.resolveRequest(requestId: requestId, decision: decision)
            }
        }
    }

    private func setupAsync() async {
        appState.notificationPermissionGranted = await notificationManager.requestPermission()
        print("[AppCoordinator] Notification permission: \(appState.notificationPermissionGranted)")

        await pendingManager.setOnTimeout { [weak self] requestId in
            guard let self else { return }
            Task { @MainActor in
                self.notificationManager.removeNotification(identifier: requestId)
                await self.refreshPendingRequests()
                self.appState.addRecentEvent(
                    toolName: "Timeout",
                    kind: .timeout,
                    sessionId: ""
                )
            }
        }
    }

    // MARK: - Webhook Server

    func ntfyConfigChanged() {
        if appState.ntfyConfig.isEnabled {
            startWebhookServer()
        } else {
            stopWebhookServer()
        }
    }

    private func startWebhookServer() {
        stopWebhookServer()

        let server = WebhookServer(
            port: appState.ntfyConfig.webhookPort,
            secret: appState.ntfyConfig.webhookSecret
        )

        server.onWebhookResponse = { [weak self] requestId, decision in
            guard let self else { return }
            Task { @MainActor in
                await self.resolveRequest(requestId: requestId, decision: decision)
            }
        }

        server.onStateChange = { [weak self] state in
            guard let self else { return }
            Task { @MainActor in
                self.appState.webhookServerState = state
            }
        }

        do {
            try server.start()
            webhookServer = server
            print("[AppCoordinator] Webhook server starting on port \(appState.ntfyConfig.webhookPort)")
        } catch {
            print("[AppCoordinator] Failed to start webhook server: \(error)")
            appState.webhookServerState = .failed(error.localizedDescription)
        }
    }

    private func stopWebhookServer() {
        webhookServer?.stop()
        webhookServer = nil
        appState.webhookServerState = .stopped
    }

    // MARK: - Request handling

    func resolveRequest(requestId: String, decision: PermissionDecision) async {
        let resolved = await pendingManager.resolve(
            requestId: requestId, decision: decision)
        if resolved {
            notificationManager.removeNotification(identifier: requestId)
            if let request = appState.pendingRequests.first(where: { $0.id == requestId }) {
                appState.addRecentEvent(
                    toolName: request.event.toolName,
                    kind: .permissionResponse(decision),
                    sessionId: request.event.sessionId
                )
            }
            await refreshPendingRequests()
        }
    }

    private func handlePermissionRequest(
        event: PermissionRequestEvent, responder: IPCResponder
    ) async {
        print("[AppCoordinator] Received permission request: \(event.toolName) (\(event.requestId))")
        await pendingManager.addRequest(event: event, responder: responder)
        await refreshPendingRequests()

        if let request = await pendingManager.getRequest(event.requestId) {
            await notificationManager.showPermissionRequest(request)
            await NtfyNotifier.sendPermissionRequest(request, config: appState.ntfyConfig)
        }
    }

    private func handleNotification(event: NotificationEvent) async {
        print("[AppCoordinator] Received notification: \(event.title)")
        await notificationManager.showNotification(
            title: event.title,
            body: event.body,
            sessionId: event.sessionId
        )
        appState.addRecentEvent(
            toolName: event.title,
            kind: .notification,
            sessionId: event.sessionId
        )
    }

    private func refreshPendingRequests() async {
        appState.pendingRequests = await pendingManager.pendingRequests
    }

    func stop() {
        ipcServer?.stop()
        ipcServer = nil
        appState.ipcServerState = .stopped
        stopWebhookServer()
    }
}

extension PendingRequestManager {
    func setOnTimeout(_ handler: @escaping @Sendable (String) -> Void) {
        onTimeout = handler
    }
}

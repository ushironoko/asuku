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
    private let statusThrottler = StatusThrottler()
    private var configRefreshTask: Task<Void, Never>?

    // Quota: a dedicated actor drives bounded Codex/cost reads (kept off the fast config loop).
    private let quotaService = QuotaService(
        codexSessionsDir: QuotaService.defaultCodexSessionsDir(),
        claudeProjectsDir: QuotaService.defaultClaudeProjectsDir()
    )
    private var quotaRefreshTask: Task<Void, Never>?
    /// How often to poll Codex quota (bounded tail-scan) and re-run the throttled cost estimate.
    private let quotaRefreshInterval: Duration = .seconds(120)

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
        case .timeoutConfigChanged:
            timeoutConfigChanged()
        case .refreshQuotaCost:
            Task { await refreshCostEstimate(force: true) }
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

            server.onStatusUpdate = { [weak self] event in
                guard let self else { return }
                Task { await self.statusThrottler.receive(event) }
            }

            server.onDisconnect = { [weak self] requestId in
                guard let self else { return }
                if let requestId {
                    Task { @MainActor in
                        self.notificationManager.removeNotification(identifier: requestId)
                        await self.pendingManager.remove(requestId: requestId)
                        await self.refreshPendingRequests()
                        self.appState.addRecentEvent(
                            toolName: "Disconnect",
                            kind: .timeout,
                            sessionId: ""
                        )
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

        await statusThrottler.setOnFlush { [weak self] events, staleSessionIds in
            self?.appState.applyStatusUpdates(events, removing: staleSessionIds)
        }

        loadConfigInBackground(appState: appState)
        let stateRef = appState
        configRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.loadConfigInBackground(appState: stateRef)
            }
        }

        await setupQuota()
    }

    // MARK: - Quota

    private func setupQuota() async {
        // Seed from the last persisted snapshot so the tab shows something (as `.stale`) immediately.
        if let snapshot = await quotaService.loadPersistedSnapshot() {
            appState.applyPersistedQuota(snapshot)
        }

        // Kick off an initial read, then poll on a bounded, single-flight cadence. Codex uses a
        // tail-scan (few files); the historical cost estimate is throttled inside QuotaService.
        await refreshCodexQuota()
        await refreshCostEstimate(force: false)

        quotaRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: self?.quotaRefreshInterval ?? .seconds(120))
                } catch {
                    return // cancelled on stop() — do not run another refresh (which could spawn app-server)
                }
                guard let self, !Task.isCancelled else { return }
                await self.refreshCodexQuota()
                await self.refreshCostEstimate(force: false)
            }
        }
    }

    private func refreshCodexQuota() async {
        // Prefer the live account/rateLimits/read (account-wide, includes pi) when the user enables it.
        let useAppServer = appState.codexAppServerConfig.isEnabled
        let observation = await quotaService.refreshCodex(now: Date(), useAppServer: useAppServer)
        appState.updateCodexQuota(observation)
        await persistQuota()
    }

    private func refreshCostEstimate(force: Bool) async {
        let estimate = await quotaService.refreshCost(now: Date(), force: force)
        appState.updateCostEstimate(estimate)
        await persistQuota()
    }

    private func persistQuota() async {
        await quotaService.persist(appState.currentQuotaSnapshot())
    }

    // MARK: - Timeout Config

    private func timeoutConfigChanged() {
        let effectiveTimeout = appState.timeoutConfig.effectiveTimeout
        Task {
            await pendingManager.rescheduleTimeouts(effectiveTimeout: effectiveTimeout)
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
        event: PermissionRequestEvent, responder: any IPCResponding
    ) async {
        print("[AppCoordinator] Received permission request: \(event.toolName) (\(event.requestId))")
        appState.trackToolUse(toolName: event.toolName)
        await pendingManager.addRequest(
            event: event,
            responder: responder,
            timeoutSeconds: appState.timeoutConfig.effectiveTimeout
        )
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
        configRefreshTask?.cancel()
        configRefreshTask = nil
        quotaRefreshTask?.cancel()
        quotaRefreshTask = nil
        Task { await statusThrottler.stop() }
        Task { await quotaService.cancelInFlight() }
    }

    nonisolated private func loadConfigInBackground(appState: AppState) {
        Task.detached {
            let plugins = ConfigReader.readEnabledPlugins()
            let history = ConfigReader.readSessionHistory()
            let toolUsage = TelemetryReader.readToolUsage()
            await MainActor.run {
                appState.updatePlugins(plugins)
                appState.updateSessionHistory(history)
                appState.updateToolUsage(toolUsage)
            }
        }
    }
}

extension PendingRequestManager {
    func setOnTimeout(_ handler: @escaping @Sendable (String) -> Void) {
        onTimeout = handler
    }
}

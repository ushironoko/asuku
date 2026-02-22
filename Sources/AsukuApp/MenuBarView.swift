import AsukuAppCore
import AsukuShared
import SwiftUI

struct MenuBarView: View {
    let appState: AppState
    let dispatch: @MainActor (AppAction) -> Void
    @Environment(\.openWindow) private var openWindow
    @State private var installAlertMessage: String?
    @State private var showInstallAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("asuku")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(appState.ipcServerState.isRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(appState.ipcServerState.isRunning ? "Running" : "Stopped")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Divider()

            // Pending requests
            if appState.pendingRequests.isEmpty {
                Text("No pending requests")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            } else {
                Text("Pending Requests (\(appState.pendingRequests.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)

                ForEach(appState.pendingRequests) { request in
                    PendingRequestRow(request: request, dispatch: dispatch)
                }
            }

            Divider()

            // Recent activity
            if !appState.recentEvents.isEmpty {
                Text("Recent Activity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)

                ForEach(appState.recentEvents.prefix(5)) { event in
                    HStack {
                        Image(systemName: event.kind.iconName)
                            .foregroundStyle(event.kind.iconColor)
                            .font(.caption)
                        Text(event.displayText)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(event.timeText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                }

                Divider()
            }

            // Actions
            Button("Install Hook...") {
                Task { @MainActor in
                    let result = await HookInstaller.install()
                    switch result {
                    case .success(let hookPath, let settingsPath):
                        installAlertMessage =
                            "Hook installed successfully.\n\nBinary: \(hookPath)\nSettings: \(settingsPath)"
                    case .failure(let error):
                        installAlertMessage = "Install failed:\n\(error)"
                    }
                    showInstallAlert = true
                }
            }
            .padding(.horizontal, 12)

            Button("Settings...") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            .padding(.horizontal, 12)

            Divider()

            Button("Quit asuku") {
                dispatch(.stop)
                NSApplication.shared.terminate(nil)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .frame(width: 320)
        .alert("Install Hook", isPresented: $showInstallAlert) {
            Button("OK") {}
        } message: {
            Text(installAlertMessage ?? "")
        }
    }
}

struct PendingRequestRow: View {
    let request: PendingRequest
    let dispatch: @MainActor (AppAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(request.displayTitle)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(.primary)

            HStack {
                Text(request.event.cwd)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }

            HStack(spacing: 8) {
                Button("Allow") {
                    dispatch(.resolveRequest(requestId: request.id, decision: .allow))
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.small)

                Button("Deny") {
                    dispatch(.resolveRequest(requestId: request.id, decision: .deny))
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)

                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

// MARK: - RecentEvent.Kind display helpers

extension RecentEvent.Kind {
    var iconName: String {
        switch self {
        case .notification: return "bell"
        case .permissionResponse(.allow): return "checkmark.circle"
        case .permissionResponse(.deny): return "xmark.circle"
        case .timeout: return "clock"
        }
    }

    var iconColor: Color {
        switch self {
        case .notification: return .blue
        case .permissionResponse(.allow): return .green
        case .permissionResponse(.deny): return .red
        case .timeout: return .orange
        }
    }
}

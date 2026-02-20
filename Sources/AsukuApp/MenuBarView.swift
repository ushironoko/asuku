import AsukuShared
import SwiftUI

struct MenuBarView: View {
    let appState: AppState
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
                    .fill(appState.isServerRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(appState.isServerRunning ? "Running" : "Stopped")
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
                    PendingRequestRow(request: request, appState: appState)
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
                        Image(
                            systemName: event.isNotification
                                ? "bell"
                                : (event.decision == .allow
                                    ? "checkmark.circle" : "xmark.circle")
                        )
                        .foregroundStyle(
                            event.isNotification
                                ? .blue : (event.decision == .allow ? .green : .red))
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
                appState.stop()
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
    let appState: AppState

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
                    Task { @MainActor in
                        await appState.resolveRequest(
                            requestId: request.id, decision: .allow)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.small)

                Button("Deny") {
                    Task { @MainActor in
                        await appState.resolveRequest(
                            requestId: request.id, decision: .deny)
                    }
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

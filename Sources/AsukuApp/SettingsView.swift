import AsukuAppCore
import AsukuShared
import SwiftUI

struct SettingsView: View {
    @Bindable var appState: AppState
    let dispatch: @MainActor (AppAction) -> Void
    @State private var launchAtLogin = false
    @State private var hookInstalled = false
    @State private var ntfySetupExpanded = false
    @State private var webhookPortText = ""

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LaunchAtLogin.setEnabled(newValue)
                    }
            }

            Section("Notification") {
                HStack {
                    Text("Permission")
                    Spacer()
                    if appState.notificationPermissionGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not Granted", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }

                if !appState.notificationPermissionGranted {
                    Button("Open Notification Settings") {
                        if let url = URL(
                            string:
                                "x-apple.systempreferences:com.apple.Notifications-Settings")
                        {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }

            Section("iPhone Notifications (ntfy)") {
                Toggle("Enable ntfy notifications", isOn: $appState.ntfyConfig.isEnabled)
                    .onChange(of: appState.ntfyConfig.isEnabled) { _, _ in
                        appState.updateNtfyConfig(appState.ntfyConfig)
                        dispatch(.ntfyConfigChanged)
                    }

                if appState.ntfyConfig.isEnabled {
                    HStack {
                        Text("Topic")
                        Spacer()
                        TextField("asuku-xxxx", text: $appState.ntfyConfig.topic)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 220)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: appState.ntfyConfig.topic) { _, _ in
                                appState.updateNtfyConfig(appState.ntfyConfig)
                            }
                    }

                    HStack {
                        Text("Server URL")
                        Spacer()
                        TextField("https://ntfy.sh", text: $appState.ntfyConfig.serverURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 220)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: appState.ntfyConfig.serverURL) { _, _ in
                                appState.updateNtfyConfig(appState.ntfyConfig)
                            }
                    }

                    if NtfyConfig.validateServerURL(appState.ntfyConfig.serverURL) == .insecure {
                        Text(
                            "Warning: HTTP is insecure for remote servers. Use HTTPS to protect notification content."
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }

                    HStack {
                        Text("Webhook URL")
                        Spacer()
                        TextField(
                            "https://xxxx.trycloudflare.com",
                            text: $appState.ntfyConfig.webhookBaseURL
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: appState.ntfyConfig.webhookBaseURL) { _, _ in
                            appState.updateNtfyConfig(appState.ntfyConfig)
                        }
                    }

                    HStack {
                        Text("Webhook Port")
                        Spacer()
                        TextField("8945", text: $webhookPortText)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 80)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: webhookPortText) { _, newValue in
                                if let port = UInt16(newValue) {
                                    appState.ntfyConfig.webhookPort = port
                                    appState.updateNtfyConfig(appState.ntfyConfig)
                                }
                            }
                    }

                    HStack {
                        Text("Webhook Server")
                        Spacer()
                        Circle()
                            .fill(
                                appState.webhookServerState.isRunning
                                    ? Color.green : Color.red
                            )
                            .frame(width: 8, height: 8)
                        Text(
                            appState.webhookServerState.isRunning ? "Running" : "Stopped"
                        )
                    }

                    if let error = appState.webhookServerState.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button("Restart Webhook Server") {
                        dispatch(.ntfyConfigChanged)
                    }
                    .disabled(!appState.ntfyConfig.isEnabled)

                    DisclosureGroup("Setup Instructions", isExpanded: $ntfySetupExpanded) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("1. Install ntfy app on iPhone")
                            Text("2. Subscribe to topic: \(appState.ntfyConfig.topic)")
                                .textSelection(.enabled)

                            Divider()

                            Text("Option A: Docker (recommended)")
                                .fontWeight(.semibold)
                            Text("3. Run: docker/start.sh")
                                .font(.caption)
                                .textSelection(.enabled)
                            Text("   Or with self-hosted ntfy:")
                                .font(.caption)
                            Text("   docker/start.sh --selfhosted")
                                .font(.caption)
                                .textSelection(.enabled)
                            Text("4. Paste the printed URLs into fields above")

                            Divider()

                            Text("Option B: Manual")
                                .fontWeight(.semibold)
                            Text("3. Install cloudflared:")
                            Text("   brew install cloudflare/cloudflare/cloudflared")
                                .font(.caption)
                                .textSelection(.enabled)
                            Text("4. Start tunnel:")
                            Text(
                                "   cloudflared tunnel --url http://localhost:\(appState.ntfyConfig.webhookPort)"
                            )
                            .font(.caption)
                            .textSelection(.enabled)
                            Text("5. Paste the tunnel URL into Webhook URL above")

                            Divider()

                            Text("Note: Quick Tunnel URLs change on each restart.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("For permanent URLs, use Named Tunnels.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
            }

            Section("Server") {
                HStack {
                    Text("Status")
                    Spacer()
                    Circle()
                        .fill(appState.ipcServerState.isRunning ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(appState.ipcServerState.isRunning ? "Running" : "Stopped")
                }

                if let error = appState.ipcServerState.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack {
                    Text("Socket Path")
                    Spacer()
                    Text((try? SocketPath.resolve()) ?? "Unknown")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Hook") {
                HStack {
                    Text("Claude Code Hook")
                    Spacer()
                    if hookInstalled {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not Installed", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Install Hook to Claude Code") {
                    Task { @MainActor in
                        let _ = await HookInstaller.install()
                        hookInstalled = HookInstaller.isInstalled()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 450, maxWidth: 450, minHeight: 380, maxHeight: 700)
        .onAppear {
            launchAtLogin = LaunchAtLogin.isEnabled
            hookInstalled = HookInstaller.isInstalled()
            webhookPortText = String(appState.ntfyConfig.webhookPort)
        }
    }
}

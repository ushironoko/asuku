import SwiftUI

struct SettingsView: View {
    let appState: AppState
    @State private var launchAtLogin = false
    @State private var hookInstalled = false

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

            Section("Server") {
                HStack {
                    Text("Status")
                    Spacer()
                    Circle()
                        .fill(appState.isServerRunning ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(appState.isServerRunning ? "Running" : "Stopped")
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
        .frame(width: 450, height: 380)
        .onAppear {
            launchAtLogin = LaunchAtLogin.isEnabled
            hookInstalled = HookInstaller.isInstalled()
        }
    }
}

// Import for SocketPath
import AsukuShared

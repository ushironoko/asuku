import AppKit
import AsukuAppCore
import AsukuShared
import SwiftUI

struct DashboardView: View {
    let appState: AppState
    @State private var selectedTab = "sessions"

    var body: some View {
        TabView(selection: $selectedTab) {
            ActiveSessionsTab(sessions: appState.activeSessions)
                .tabItem { Label("Sessions", systemImage: "terminal") }
                .tag("sessions")

            PluginsTab(plugins: appState.enabledPlugins)
                .tabItem { Label("Plugins", systemImage: "puzzlepiece") }
                .tag("plugins")

            HistoryTab(entries: appState.sessionHistory)
                .tabItem { Label("History", systemImage: "clock") }
                .tag("history")
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

// MARK: - Active Sessions Tab

private struct ActiveSessionsTab: View {
    let sessions: [SessionStatus]

    var body: some View {
        if sessions.isEmpty {
            ContentUnavailableView(
                "No Active Sessions",
                systemImage: "terminal",
                description: Text("Sessions will appear when Claude Code is running.")
            )
        } else {
            List(sessions) { session in
                SessionRow(session: session)
            }
        }
    }
}

private struct SessionRow: View {
    let session: SessionStatus
    @State private var showQRSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.modelName ?? "Unknown")
                    .font(.headline)
                if let agent = session.agentName {
                    Text(agent)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Spacer()
                if session.remoteControlURL != nil {
                    Button { showQRSheet = true } label: {
                        Image(systemName: "qrcode")
                    }
                    .buttonStyle(.borderless)
                    .help("Show remote control QR code")
                }
                Text(session.lastUpdated, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let percent = session.contextUsedPercent {
                HStack(spacing: 6) {
                    Text("Context")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: Double(percent), total: 100)
                        .tint(contextColor(for: percent))
                    Text("\(percent)%")
                        .font(.caption)
                        .monospacedDigit()
                }
            }

            HStack(spacing: 12) {
                if let cost = session.totalCost {
                    Label(String(format: "$%.4f", cost), systemImage: "dollarsign.circle")
                        .font(.caption)
                }
                if let added = session.statusline.cost?.totalLinesAdded,
                    let removed = session.statusline.cost?.totalLinesRemoved
                {
                    Label("+\(added) -\(removed)", systemImage: "text.line.first.and.arrowtriangle.forward")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let path = session.projectDir {
                Text(abbreviatePath(path))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text("Session: \(String(session.sessionId.prefix(8)))...")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showQRSheet) {
            QRCodeSheet(session: session)
        }
    }

    private func contextColor(for percent: Int) -> Color {
        if percent > 80 { return .red }
        if percent > 60 { return .orange }
        return .secondary
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// MARK: - Plugins Tab

private struct PluginsTab: View {
    let plugins: [EnabledPlugin]

    var body: some View {
        if plugins.isEmpty {
            ContentUnavailableView(
                "No Plugins",
                systemImage: "puzzlepiece",
                description: Text("Install plugins in Claude Code to see them here.")
            )
        } else {
            List(plugins) { plugin in
                HStack {
                    VStack(alignment: .leading) {
                        Text(plugin.name)
                            .font(.body)
                        if !plugin.marketplace.isEmpty {
                            Text(plugin.marketplace)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if !plugin.version.isEmpty {
                        Text(plugin.version)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Circle()
                        .fill(plugin.isEnabled ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(plugin.isEnabled ? "Enabled" : "Disabled")
                        .font(.caption)
                        .foregroundStyle(plugin.isEnabled ? .primary : .secondary)
                }
            }
        }
    }
}

// MARK: - History Tab

private struct HistoryTab: View {
    let entries: [SessionHistoryEntry]

    var body: some View {
        if entries.isEmpty {
            ContentUnavailableView(
                "No History",
                systemImage: "clock",
                description: Text("Session history will appear after using Claude Code.")
            )
        } else {
            List(entries) { entry in
                HistoryRow(entry: entry)
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: SessionHistoryEntry
    @State private var copied = false
    @State private var feedbackTask: Task<Void, Never>?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayText.isEmpty ? entry.sessionId : entry.displayText)
                    .font(.body)
                    .lineLimit(1)
                if !entry.projectPath.isEmpty {
                    Text(entry.projectPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Button {
                copyResumeCommand()
            } label: {
                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .foregroundStyle(copied ? .green : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .help("Copy: claude --resume \(entry.sessionId)")
            VStack(alignment: .trailing) {
                Text(String(entry.sessionId.prefix(8)))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospaced()
                Text(entry.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button("Copy resume command") {
                copyResumeCommand()
            }
            Button("Copy session ID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.sessionId, forType: .string)
            }
        }
    }

    private func copyResumeCommand() {
        let escaped = entry.sessionId.replacingOccurrences(of: "'", with: "'\\''")
        let command = "claude --resume '\(escaped)'"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copied = true
        feedbackTask?.cancel()
        feedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { copied = false }
        }
    }
}

// MARK: - QR Code Sheet

private struct QRCodeSheet: View {
    let session: SessionStatus
    @State private var copied = false
    @State private var feedbackTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Remote Control")
                .font(.headline)
            Text("Session: \(String(session.sessionId.prefix(8)))...")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let url = session.remoteControlURL,
                let qrImage = QRCodeGenerator.generate(from: url.absoluteString)
            {
                Image(nsImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
            }

            if let url = session.remoteControlURL {
                Text(url.absoluteString)
                    .font(.caption)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    copied = true
                    feedbackTask?.cancel()
                    feedbackTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(2))
                        if !Task.isCancelled { copied = false }
                    }
                } label: {
                    Label(
                        copied ? "Copied!" : "Copy URL",
                        systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc"
                    )
                }
                .buttonStyle(.borderedProminent)
            }

            Button("Close") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(width: 300)
    }
}

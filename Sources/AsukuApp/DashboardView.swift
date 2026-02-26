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
            }
        }
    }
}

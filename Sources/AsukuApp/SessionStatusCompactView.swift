import AsukuAppCore
import AsukuShared
import SwiftUI

/// Compact status view displayed in the menu bar dropdown
struct SessionStatusCompactView: View {
    let session: SessionStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Model name + agent badge
            HStack {
                Label(session.modelName ?? "Unknown", systemImage: "cpu")
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                if let agent = session.agentName {
                    Text(agent)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            // Context window usage
            if let percent = session.contextUsedPercent {
                HStack(spacing: 6) {
                    Text("Context")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ProgressView(value: Double(percent), total: 100)
                        .tint(contextColor(for: percent))
                    Text("\(percent)%")
                        .font(.caption2)
                        .monospacedDigit()
                }
            }

            // Cost + lines changed
            HStack(spacing: 8) {
                if let cost = session.totalCost {
                    Text(String(format: "$%.4f", cost))
                        .font(.caption2)
                        .monospacedDigit()
                }
                if let added = session.statusline.cost?.totalLinesAdded,
                    let removed = session.statusline.cost?.totalLinesRemoved
                {
                    Text("+\(added) -\(removed)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // Project path
            if let path = session.projectDir {
                Text(abbreviatePath(path))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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

import AsukuAppCore
import Charts
import SwiftUI

struct UsageTab: View {
    let snapshot: ToolUsageSnapshot
    let realTimeCounts: [String: ToolCount]

    @State private var selectedCategories: Set<ToolCategory> = Set(ToolCategory.allCases)

    private static let categoryColors: [ToolCategory: Color] = [
        .tool: .blue,
        .agent: .purple,
        .skill: .green,
        .command: .orange,
    ]

    var body: some View {
        let entries = ToolUsageMerger.merge(snapshot: snapshot, realTimeCounts: realTimeCounts)
        if entries.isEmpty {
            ContentUnavailableView(
                "No Usage Data",
                systemImage: "chart.bar",
                description: Text(
                    "Tool usage data will appear after using Claude Code.\nReads from ~/.claude/telemetry/"
                )
            )
        } else {
            let filtered = entries.filter { selectedCategories.contains($0.category) }
            let presentCategories = Set(entries.map(\.category))
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    legendView(presentCategories: presentCategories)
                    chartView(entries: filtered)
                }
                .padding()
            }
        }
    }

    private func chartView(entries: [ToolUsageEntry]) -> some View {
        Chart(entries) { entry in
            BarMark(
                x: .value("Count", entry.count),
                y: .value("Tool", entry.name)
            )
            .foregroundStyle(by: .value("Category", entry.category.rawValue))
        }
        .chartForegroundStyleScale([
            "tool": Self.categoryColors[.tool]!,
            "agent": Self.categoryColors[.agent]!,
            "skill": Self.categoryColors[.skill]!,
            "command": Self.categoryColors[.command]!,
        ])
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.caption)
            }
        }
        .chartLegend(.hidden)
        .frame(height: max(CGFloat(entries.count) * 28, 200))
    }

    private func legendView(presentCategories: Set<ToolCategory>) -> some View {
        HStack(spacing: 12) {
            ForEach(
                ToolCategory.allCases.filter { presentCategories.contains($0) },
                id: \.rawValue
            ) { category in
                let isSelected = selectedCategories.contains(category)
                Button {
                    if isSelected {
                        if selectedCategories.count > 1 {
                            selectedCategories.remove(category)
                        }
                    } else {
                        selectedCategories.insert(category)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(
                                isSelected
                                    ? Self.categoryColors[category, default: .gray] : Color.gray
                            )
                            .frame(width: 8, height: 8)
                        Text(category.rawValue)
                            .font(.caption)
                    }
                    .foregroundStyle(isSelected ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

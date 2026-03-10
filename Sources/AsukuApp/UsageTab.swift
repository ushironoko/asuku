import AsukuAppCore
import Charts
import SwiftUI

struct UsageTab: View {
    let snapshot: ToolUsageSnapshot
    let realTimeCounts: [String: ToolCount]

    @State private var selectedCategories: Set<ToolCategory> = Set(ToolCategory.allCases)

    private var mergedEntries: [ToolUsageEntry] {
        ToolUsageMerger.merge(snapshot: snapshot, realTimeCounts: realTimeCounts)
    }

    private var filteredEntries: [ToolUsageEntry] {
        mergedEntries.filter { selectedCategories.contains($0.category) }
    }

    var body: some View {
        if mergedEntries.isEmpty {
            ContentUnavailableView(
                "No Usage Data",
                systemImage: "chart.bar",
                description: Text(
                    "Tool usage data will appear after using Claude Code.\nReads from ~/.claude/telemetry/"
                )
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    legendView
                    chartView
                }
                .padding()
            }
        }
    }

    private var chartView: some View {
        Chart(filteredEntries) { entry in
            BarMark(
                x: .value("Count", entry.count),
                y: .value("Tool", entry.name)
            )
            .foregroundStyle(by: .value("Category", entry.category.rawValue))
        }
        .chartForegroundStyleScale([
            "tool": Color.blue,
            "agent": Color.purple,
            "skill": Color.green,
            "command": Color.orange,
        ])
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.caption)
            }
        }
        .chartLegend(.hidden)
        .frame(height: max(CGFloat(filteredEntries.count) * 28, 200))
    }

    private var legendView: some View {
        HStack(spacing: 12) {
            ForEach(ToolCategory.allCases, id: \.rawValue) { category in
                let isSelected = selectedCategories.contains(category)
                Button {
                    if isSelected {
                        // Don't allow deselecting all
                        if selectedCategories.count > 1 {
                            selectedCategories.remove(category)
                        }
                    } else {
                        selectedCategories.insert(category)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isSelected ? colorForCategory(category) : Color.gray)
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

    private func colorForCategory(_ category: ToolCategory) -> Color {
        switch category {
        case .tool: .blue
        case .agent: .purple
        case .skill: .green
        case .command: .orange
        }
    }
}

import Foundation
import Testing

@testable import AsukuAppCore

@Suite("ToolUsageMerger Tests")
struct ToolUsageMergerTests {

    @Test("Snapshot with empty realTime returns snapshot entries")
    func snapshotOnly() {
        let snapshot = ToolUsageSnapshot(
            entries: [
                ToolUsageEntry(name: "Read", category: .tool, count: 10),
                ToolUsageEntry(name: "Edit", category: .tool, count: 5),
            ],
            totalCount: 15
        )

        let result = ToolUsageMerger.merge(snapshot: snapshot, realTimeCounts: [:])
        #expect(result.count == 2)
        #expect(result[0].name == "Read")
        #expect(result[0].count == 10)
        #expect(result[1].name == "Edit")
        #expect(result[1].count == 5)
    }

    @Test("Empty snapshot with realTime returns realTime entries")
    func realTimeOnly() {
        let realTime: [String: ToolCount] = [
            "Bash": ToolCount(count: 3, category: .tool),
            "commit": ToolCount(count: 1, category: .skill),
        ]

        let result = ToolUsageMerger.merge(snapshot: .empty, realTimeCounts: realTime)
        #expect(result.count == 2)
        #expect(result[0].name == "Bash")
        #expect(result[0].count == 3)
        #expect(result[1].name == "commit")
        #expect(result[1].count == 1)
    }

    @Test("Overlapping tool names add counts")
    func mergeOverlapping() {
        let snapshot = ToolUsageSnapshot(
            entries: [
                ToolUsageEntry(name: "Read", category: .tool, count: 10)
            ],
            totalCount: 10
        )
        let realTime: [String: ToolCount] = [
            "Read": ToolCount(count: 5, category: .tool)
        ]

        let result = ToolUsageMerger.merge(snapshot: snapshot, realTimeCounts: realTime)
        #expect(result.count == 1)
        #expect(result[0].name == "Read")
        #expect(result[0].count == 15)
    }

    @Test("Merged result is sorted by count descending")
    func mergeSortOrder() {
        let snapshot = ToolUsageSnapshot(
            entries: [
                ToolUsageEntry(name: "Read", category: .tool, count: 5),
                ToolUsageEntry(name: "Bash", category: .tool, count: 20),
            ],
            totalCount: 25
        )
        let realTime: [String: ToolCount] = [
            "Read": ToolCount(count: 30, category: .tool),  // 5 + 30 = 35, overtakes Bash
        ]

        let result = ToolUsageMerger.merge(snapshot: snapshot, realTimeCounts: realTime)
        #expect(result[0].name == "Read")
        #expect(result[0].count == 35)
        #expect(result[1].name == "Bash")
        #expect(result[1].count == 20)
    }

    @Test("Both empty returns empty array")
    func bothEmpty() {
        let result = ToolUsageMerger.merge(snapshot: .empty, realTimeCounts: [:])
        #expect(result.isEmpty)
    }
}

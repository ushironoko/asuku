import Foundation

// MARK: - Tool Category

public enum ToolCategory: String, Sendable, CaseIterable, Equatable {
    case tool
    case agent
    case skill
    case command
}

// MARK: - Tool Usage Entry

public struct ToolUsageEntry: Sendable, Equatable, Identifiable {
    public var id: String { "\(category.rawValue):\(name)" }
    public let name: String
    public let category: ToolCategory
    public let count: Int

    public init(name: String, category: ToolCategory, count: Int) {
        self.name = name
        self.category = category
        self.count = count
    }
}

// MARK: - Tool Usage Snapshot

public struct ToolUsageSnapshot: Sendable, Equatable {
    public let entries: [ToolUsageEntry]
    public let totalCount: Int

    public init(entries: [ToolUsageEntry], totalCount: Int) {
        self.entries = entries
        self.totalCount = totalCount
    }

    public static let empty = ToolUsageSnapshot(entries: [], totalCount: 0)
}

// MARK: - Tool Count (for real-time tracking)

public struct ToolCount: Sendable, Equatable {
    public let count: Int
    public let category: ToolCategory

    public init(count: Int, category: ToolCategory) {
        self.count = count
        self.category = category
    }
}

// MARK: - Persistence

public enum ToolCountStore {
    private static let key = "toolUsage.realTimeCounts"

    public static func load(from defaults: UserDefaults = .standard) -> [String: ToolCount] {
        guard let data = defaults.data(forKey: key),
            let stored = try? JSONDecoder().decode([String: StoredToolCount].self, from: data)
        else { return [:] }
        var result: [String: ToolCount] = [:]
        for (name, stored) in stored {
            if let category = ToolCategory(rawValue: stored.category) {
                result[name] = ToolCount(count: stored.count, category: category)
            }
        }
        return result
    }

    public static func save(
        _ counts: [String: ToolCount], to defaults: UserDefaults = .standard
    ) {
        var stored: [String: StoredToolCount] = [:]
        for (name, tc) in counts {
            stored[name] = StoredToolCount(count: tc.count, category: tc.category.rawValue)
        }
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: key)
        }
    }

    private struct StoredToolCount: Codable {
        let count: Int
        let category: String
    }
}

// MARK: - Merger

public enum ToolUsageMerger {
    public static func merge(
        snapshot: ToolUsageSnapshot,
        realTimeCounts: [String: ToolCount]
    ) -> [ToolUsageEntry] {
        var merged: [String: (name: String, category: ToolCategory, count: Int)] = [:]

        for entry in snapshot.entries {
            merged[entry.id] = (entry.name, entry.category, entry.count)
        }

        for (name, toolCount) in realTimeCounts {
            let key = "\(toolCount.category.rawValue):\(name)"
            if let existing = merged[key] {
                merged[key] = (existing.name, existing.category, existing.count + toolCount.count)
            } else {
                merged[key] = (name, toolCount.category, toolCount.count)
            }
        }

        return merged.values
            .map { ToolUsageEntry(name: $0.name, category: $0.category, count: $0.count) }
            .sorted { $0.count > $1.count }
    }
}

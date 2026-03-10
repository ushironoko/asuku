import Foundation

/// Reads Claude Code telemetry JSONL files and aggregates tool usage statistics.
/// Designed to run off the main actor.
public enum TelemetryReader {
    private static var telemetryDir: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/telemetry").path
    }

    private static let targetEventNames: Set<String> = [
        "tengu_tool_use_success",
        "tengu_agent_tool_selected",
        "tengu_input_command",
    ]

    /// Maximum file size to read (50 MB). Files larger than this are skipped.
    private static let maxFileSize: UInt64 = 50 * 1024 * 1024

    /// Reads all telemetry JSONL files and returns aggregated tool usage.
    /// Pass `dirPath` to override the default telemetry directory (for testing).
    public static func readToolUsage(from dirPath: String? = nil) -> ToolUsageSnapshot {
        let dir = dirPath ?? telemetryDir
        let fm = FileManager.default

        guard let fileNames = try? fm.contentsOfDirectory(atPath: dir) else {
            return .empty
        }

        let jsonFiles = fileNames.filter { $0.hasSuffix(".json") }
        if jsonFiles.isEmpty { return .empty }

        var aggregated: [String: (name: String, count: Int, category: ToolCategory)] = [:]

        for fileName in jsonFiles {
            let filePath = (dir as NSString).appendingPathComponent(fileName)
            // Skip files exceeding size limit to avoid excessive memory usage
            if let attrs = try? fm.attributesOfItem(atPath: filePath),
                let fileSize = attrs[.size] as? UInt64,
                fileSize > maxFileSize
            {
                continue
            }
            guard let handle = FileHandle(forReadingAtPath: filePath) else { continue }
            let data = handle.readDataToEndOfFile()
            handle.closeFile()

            guard let content = String(data: data, encoding: .utf8) else { continue }

            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                guard !line.isEmpty else { continue }

                // Fast pre-filter: skip lines that don't contain any target event name
                var matchesAny = false
                for eventName in targetEventNames {
                    if line.contains(eventName) {
                        matchesAny = true
                        break
                    }
                }
                guard matchesAny else { continue }

                if let parsed = parseToolUsageLine(line) {
                    let key = "\(parsed.category.rawValue):\(parsed.name)"
                    if let existing = aggregated[key] {
                        aggregated[key] = (existing.name, existing.count + 1, existing.category)
                    } else {
                        aggregated[key] = (parsed.name, 1, parsed.category)
                    }
                }
            }
        }

        if aggregated.isEmpty { return .empty }

        let entries = aggregated.values
            .map { ToolUsageEntry(name: $0.name, category: $0.category, count: $0.count) }
            .sorted { $0.count > $1.count }

        let totalCount = entries.reduce(0) { $0 + $1.count }
        return ToolUsageSnapshot(entries: entries, totalCount: totalCount)
    }

    /// Parses a single JSONL line. Returns the tool name and category, or nil.
    public static func parseToolUsageLine(_ line: String) -> (name: String, category: ToolCategory)?
    {
        guard let lineData = line.data(using: .utf8),
            let outer = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
            let eventData = outer["event_data"] as? [String: Any],
            let eventName = eventData["event_name"] as? String,
            targetEventNames.contains(eventName),
            let metadataString = eventData["additional_metadata"] as? String,
            let metaData = metadataString.data(using: .utf8),
            let metadata = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any]
        else {
            return nil
        }

        switch eventName {
        case "tengu_tool_use_success":
            guard let toolName = metadata["toolName"] as? String else { return nil }
            return (toolName, .tool)
        case "tengu_agent_tool_selected":
            guard let agentType = metadata["agent_type"] as? String else { return nil }
            return (agentType, .agent)
        case "tengu_input_command":
            guard let input = metadata["input"] as? String else { return nil }
            return (input, .command)
        default:
            return nil
        }
    }
}

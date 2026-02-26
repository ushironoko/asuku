import Foundation

/// Reads Claude Code configuration files from disk.
/// Designed to run off the main actor.
public enum ConfigReader {
    private static var claudeDir: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude").path
    }

    /// Reads enabled plugins by merging settings.json and installed_plugins.json
    public static func readEnabledPlugins() -> [EnabledPlugin] {
        let settingsPath = (claudeDir as NSString).appendingPathComponent("settings.json")
        let pluginsPath = (claudeDir as NSString).appendingPathComponent(
            "plugins/installed_plugins.json")

        // Read settings.json enabledPlugins
        var enabledMap: [String: Bool] = [:]
        if let data = FileManager.default.contents(atPath: settingsPath),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let enabled = json["enabledPlugins"] as? [String: Bool]
        {
            enabledMap = enabled
        }

        // Read installed_plugins.json
        var installedMap: [String: [String: Any]] = [:]
        if let data = FileManager.default.contents(atPath: pluginsPath),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let plugins = json["plugins"] as? [String: [String: Any]]
        {
            installedMap = plugins
        }

        // Merge: use all known plugin IDs from both sources
        var allPluginIds = Set(enabledMap.keys)
        allPluginIds.formUnion(installedMap.keys)

        return allPluginIds.sorted().map { pluginId in
            let parts = pluginId.split(separator: "@", maxSplits: 1)
            let name = parts.first.map(String.init) ?? pluginId
            let marketplace = parts.count > 1 ? String(parts[1]) : ""
            let isEnabled = enabledMap[pluginId] ?? false
            let installed = installedMap[pluginId]
            let version = installed?["version"] as? String ?? ""

            return EnabledPlugin(
                id: pluginId,
                name: name,
                marketplace: marketplace,
                isEnabled: isEnabled,
                version: version
            )
        }
    }

    /// Reads session history from history.jsonl using tail approach (last 64KB)
    public static func readSessionHistory(limit: Int = 20) -> [SessionHistoryEntry] {
        let path = (claudeDir as NSString).appendingPathComponent("history.jsonl")
        guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { handle.closeFile() }

        let tailBytes: UInt64 = 64 * 1024  // 64KB
        let fileSize = handle.seekToEndOfFile()
        let seekPos = fileSize > tailBytes ? fileSize - tailBytes : 0
        handle.seek(toFileOffset: seekPos)
        let data = handle.readDataToEndOfFile()

        // Handle UTF-8 multibyte boundary split
        guard
            let content = String(data: data, encoding: .utf8)
                ?? String(data: data.dropFirst(1), encoding: .utf8)
                ?? String(data: data.dropFirst(2), encoding: .utf8)
                ?? String(data: data.dropFirst(3), encoding: .utf8)
        else { return [] }

        // If we seeked past the beginning, the first line may be truncated
        var lines = content.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
        if seekPos > 0, !lines.isEmpty {
            lines.removeFirst()
        }

        return lines.suffix(limit).reversed().compactMap { line in
            guard let lineData = line.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                let sessionId = json["sessionId"] as? String
            else { return nil }

            return SessionHistoryEntry(
                id: UUID().uuidString,
                sessionId: sessionId,
                projectPath: json["project"] as? String ?? "",
                timestamp: Date(
                    timeIntervalSince1970: (json["timestamp"] as? Double ?? 0) / 1000),
                displayText: json["display"] as? String ?? ""
            )
        }
    }
}

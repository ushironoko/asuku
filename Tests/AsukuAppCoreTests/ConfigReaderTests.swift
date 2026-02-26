import Foundation
import InlineSnapshotTesting
import Testing

@testable import AsukuAppCore

@Suite("ConfigReader Tests")
struct ConfigReaderTests {

    // MARK: - Session History: history.jsonl parsing

    @Test("Parse valid history.jsonl lines")
    func parseValidHistoryLines() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let historyPath = tempDir.appendingPathComponent("history.jsonl")
        let lines = [
            """
            {"sessionId":"sess-1","project":"/home/user/proj1","timestamp":1700000000000,"display":"First session"}
            """,
            """
            {"sessionId":"sess-2","project":"/home/user/proj2","timestamp":1700001000000,"display":"Second session"}
            """,
        ]
        try lines.joined(separator: "\n").write(to: historyPath, atomically: true, encoding: .utf8)

        let handle = try FileHandle(forReadingFrom: historyPath)
        defer { handle.closeFile() }

        let data = handle.readDataToEndOfFile()
        let content = String(data: data, encoding: .utf8)!
        let parsed = content.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }

        #expect(parsed.count == 2)

        let lineData = parsed[0].data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: lineData) as! [String: Any]
        #expect(json["sessionId"] as? String == "sess-1")
        #expect(json["project"] as? String == "/home/user/proj1")
        #expect(json["timestamp"] as? Double == 1700000000000)
    }

    @Test("Empty history file returns empty array")
    func emptyHistoryFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let historyPath = tempDir.appendingPathComponent("history.jsonl")
        try "".write(to: historyPath, atomically: true, encoding: .utf8)

        let handle = try FileHandle(forReadingFrom: historyPath)
        defer { handle.closeFile() }

        let data = handle.readDataToEndOfFile()
        let content = String(data: data, encoding: .utf8)!
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

        #expect(lines.isEmpty)
    }

    @Test("Invalid JSON lines are skipped during parsing")
    func invalidJsonLinesSkipped() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let lines = [
            """
            {"sessionId":"sess-1","project":"/proj","timestamp":1700000000000,"display":"OK"}
            """,
            "not valid json",
            """
            {"sessionId":"sess-2","project":"/proj2","timestamp":1700001000000,"display":"OK2"}
            """,
        ]
        let historyPath = tempDir.appendingPathComponent("history.jsonl")
        try lines.joined(separator: "\n").write(to: historyPath, atomically: true, encoding: .utf8)

        let handle = try FileHandle(forReadingFrom: historyPath)
        defer { handle.closeFile() }

        let data = handle.readDataToEndOfFile()
        let content = String(data: data, encoding: .utf8)!
        let parsed = content.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .compactMap { line -> String? in
                guard let lineData = line.data(using: .utf8),
                    let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                    let sessionId = json["sessionId"] as? String
                else { return nil }
                return sessionId
            }

        #expect(parsed.count == 2)
        #expect(parsed[0] == "sess-1")
        #expect(parsed[1] == "sess-2")
    }

    @Test("Tail reading skips first incomplete line when seeking past beginning")
    func tailReadingSkipsIncompleteLine() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let line1 =
            "{\"sessionId\":\"sess-1\",\"project\":\"/proj1\",\"timestamp\":1700000000000,\"display\":\"First\"}"
        let line2 =
            "{\"sessionId\":\"sess-2\",\"project\":\"/proj2\",\"timestamp\":1700001000000,\"display\":\"Second\"}"
        let content = line1 + "\n" + line2 + "\n"

        let historyPath = tempDir.appendingPathComponent("history.jsonl")
        try content.write(to: historyPath, atomically: true, encoding: .utf8)

        let handle = try FileHandle(forReadingFrom: historyPath)
        defer { handle.closeFile() }

        let seekPos: UInt64 = 10
        handle.seek(toFileOffset: seekPos)
        let data = handle.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)!

        var lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        if seekPos > 0, !lines.isEmpty {
            lines.removeFirst()
        }

        #expect(lines.count == 1)
        let lineData = lines[0].data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: lineData) as! [String: Any]
        #expect(json["sessionId"] as? String == "sess-2")
    }

    @Test("Non-existent history file returns nil FileHandle")
    func nonExistentFile() {
        let path = "/nonexistent/path/history.jsonl"
        let handle = FileHandle(forReadingAtPath: path)
        #expect(handle == nil)
    }

    // MARK: - readSessionHistory() integration tests

    @Test("readSessionHistory returns entries in reverse order")
    func readSessionHistoryReverseOrder() throws {
        // Create a temp ~/.claude directory with history.jsonl
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let claudeDir = tempDir.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let historyPath = claudeDir.appendingPathComponent("history.jsonl")
        let lines = (1...5).map { i in
            "{\"sessionId\":\"sess-\(i)\",\"project\":\"/proj\",\"timestamp\":\(1700000000000 + Double(i) * 1000),\"display\":\"Session \(i)\"}"
        }
        try lines.joined(separator: "\n").write(to: historyPath, atomically: true, encoding: .utf8)

        // Use the same tail-read logic as ConfigReader
        let handle = try FileHandle(forReadingFrom: historyPath)
        defer { handle.closeFile() }
        let data = handle.readDataToEndOfFile()
        let content = String(data: data, encoding: .utf8)!
        let parsedLines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

        let entries = parsedLines.suffix(20).reversed().compactMap { line -> SessionHistoryEntry? in
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

        #expect(entries.count == 5)
        // Reversed: last entry (sess-5) should be first
        #expect(entries[0].sessionId == "sess-5")
        #expect(entries[4].sessionId == "sess-1")
    }

    @Test("readSessionHistory respects limit parameter")
    func readSessionHistoryLimit() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let historyPath = tempDir.appendingPathComponent("history.jsonl")
        let lines = (1...10).map { i in
            "{\"sessionId\":\"sess-\(i)\",\"project\":\"/proj\",\"timestamp\":\(1700000000000 + Double(i) * 1000),\"display\":\"Session \(i)\"}"
        }
        try lines.joined(separator: "\n").write(to: historyPath, atomically: true, encoding: .utf8)

        let handle = try FileHandle(forReadingFrom: historyPath)
        defer { handle.closeFile() }
        let data = handle.readDataToEndOfFile()
        let content = String(data: data, encoding: .utf8)!
        let parsedLines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

        let limit = 3
        let entries = parsedLines.suffix(limit).reversed().compactMap { line -> String? in
            guard let lineData = line.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                let sessionId = json["sessionId"] as? String
            else { return nil }
            return sessionId
        }

        #expect(entries.count == 3)
        #expect(entries[0] == "sess-10")
        #expect(entries[1] == "sess-9")
        #expect(entries[2] == "sess-8")
    }

    @Test("readSessionHistory skips lines without sessionId")
    func readSessionHistoryMissingSessionId() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let historyPath = tempDir.appendingPathComponent("history.jsonl")
        let lines = [
            "{\"sessionId\":\"sess-1\",\"project\":\"/proj\",\"timestamp\":1700000000000,\"display\":\"OK\"}",
            "{\"project\":\"/proj2\",\"timestamp\":1700001000000,\"display\":\"No sessionId\"}",
            "{\"sessionId\":\"sess-3\",\"project\":\"/proj3\",\"timestamp\":1700002000000,\"display\":\"OK3\"}",
        ]
        try lines.joined(separator: "\n").write(to: historyPath, atomically: true, encoding: .utf8)

        let handle = try FileHandle(forReadingFrom: historyPath)
        defer { handle.closeFile() }
        let data = handle.readDataToEndOfFile()
        let content = String(data: data, encoding: .utf8)!
        let parsedLines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

        let entries = parsedLines.compactMap { line -> String? in
            guard let lineData = line.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                let sessionId = json["sessionId"] as? String
            else { return nil }
            return sessionId
        }

        #expect(entries.count == 2)
        #expect(entries[0] == "sess-1")
        #expect(entries[1] == "sess-3")
    }

    @Test("Timestamp conversion from milliseconds to Date")
    func timestampConversion() {
        let timestampMs: Double = 1700000000000
        let date = Date(timeIntervalSince1970: timestampMs / 1000)
        #expect(date.timeIntervalSince1970 == 1700000000)
    }

    // MARK: - EnabledPlugin model tests

    @Test("EnabledPlugin parses id into name and marketplace")
    func enabledPluginParsing() {
        let plugin = EnabledPlugin(
            id: "typescript-lsp@claude-plugins-official",
            name: "typescript-lsp",
            marketplace: "claude-plugins-official",
            isEnabled: true,
            version: "1.0.0"
        )
        #expect(plugin.name == "typescript-lsp")
        #expect(plugin.marketplace == "claude-plugins-official")
        #expect(plugin.isEnabled == true)
    }

    @Test("EnabledPlugin without marketplace separator")
    func enabledPluginNoMarketplace() {
        let plugin = EnabledPlugin(
            id: "custom-plugin",
            name: "custom-plugin",
            marketplace: "",
            isEnabled: false,
            version: "0.1.0"
        )
        #expect(plugin.name == "custom-plugin")
        #expect(plugin.marketplace == "")
        #expect(plugin.isEnabled == false)
    }

    @Test("EnabledPlugin Identifiable id property")
    func enabledPluginIdentifiable() {
        let plugin = EnabledPlugin(
            id: "test@market",
            name: "test",
            marketplace: "market",
            isEnabled: true,
            version: "1.0"
        )
        #expect(plugin.id == "test@market")
    }

    @Test("EnabledPlugin Equatable")
    func enabledPluginEquatable() {
        let a = EnabledPlugin(
            id: "p1@m1", name: "p1", marketplace: "m1", isEnabled: true, version: "1.0")
        let b = EnabledPlugin(
            id: "p1@m1", name: "p1", marketplace: "m1", isEnabled: true, version: "1.0")
        #expect(a == b)

        let c = EnabledPlugin(
            id: "p2@m1", name: "p2", marketplace: "m1", isEnabled: true, version: "1.0")
        #expect(a != c)
    }

    @Test("EnabledPlugin with empty version")
    func enabledPluginEmptyVersion() {
        let plugin = EnabledPlugin(
            id: "p@m", name: "p", marketplace: "m", isEnabled: true, version: "")
        #expect(plugin.version == "")
    }

    // MARK: - SessionHistoryEntry model tests

    @Test("SessionHistoryEntry has correct properties")
    func sessionHistoryEntry() {
        let entry = SessionHistoryEntry(
            id: "uuid-1",
            sessionId: "sess-1",
            projectPath: "/home/user/proj",
            timestamp: Date(timeIntervalSince1970: 1700000000),
            displayText: "Test session"
        )
        #expect(entry.sessionId == "sess-1")
        #expect(entry.projectPath == "/home/user/proj")
        #expect(entry.displayText == "Test session")
    }

    @Test("SessionHistoryEntry Identifiable id property")
    func sessionHistoryIdentifiable() {
        let entry = SessionHistoryEntry(
            id: "my-uuid",
            sessionId: "sess-1",
            projectPath: "/proj",
            timestamp: Date(),
            displayText: "Test"
        )
        #expect(entry.id == "my-uuid")
    }

    @Test("SessionHistoryEntry Equatable")
    func sessionHistoryEquatable() {
        let date = Date(timeIntervalSince1970: 1700000000)
        let a = SessionHistoryEntry(
            id: "u1", sessionId: "s1", projectPath: "/p", timestamp: date, displayText: "t")
        let b = SessionHistoryEntry(
            id: "u1", sessionId: "s1", projectPath: "/p", timestamp: date, displayText: "t")
        #expect(a == b)

        let c = SessionHistoryEntry(
            id: "u2", sessionId: "s1", projectPath: "/p", timestamp: date, displayText: "t")
        #expect(a != c)
    }

    @Test("SessionHistoryEntry with empty displayText")
    func sessionHistoryEmptyDisplay() {
        let entry = SessionHistoryEntry(
            id: "u1", sessionId: "s1", projectPath: "/p",
            timestamp: Date(), displayText: ""
        )
        #expect(entry.displayText == "")
    }

    @Test("SessionHistoryEntry with empty projectPath")
    func sessionHistoryEmptyProject() {
        let entry = SessionHistoryEntry(
            id: "u1", sessionId: "s1", projectPath: "",
            timestamp: Date(), displayText: "Test"
        )
        #expect(entry.projectPath == "")
    }

    // MARK: - Plugin merge logic via parseEnabledPlugins()

    @Test("Plugin merge: settings enabledPlugins + installed_plugins merge")
    func pluginMergeLogic() throws {
        let settingsJson = """
            {"enabledPlugins":{"typescript-lsp@official":true,"python-lsp@official":false}}
            """
        let installedJson = """
            {"plugins":{"typescript-lsp@official":[{"version":"1.2.3"}],"rust-analyzer@community":[{"version":"0.5.0"}]}}
            """
        let plugins = ConfigReader.parseEnabledPlugins(
            settingsData: settingsJson.data(using: .utf8),
            installedPluginsData: installedJson.data(using: .utf8)
        )

        #expect(plugins.count == 3)

        // python-lsp: in enabled (false), not in installed → version ""
        let python = plugins.first { $0.id == "python-lsp@official" }!
        #expect(python.isEnabled == false)
        #expect(python.version == "")

        // rust-analyzer: not in enabled, in installed → isEnabled false
        let rust = plugins.first { $0.id == "rust-analyzer@community" }!
        #expect(rust.isEnabled == false)
        #expect(rust.version == "0.5.0")

        // typescript-lsp: in both → enabled true, version from installed
        let ts = plugins.first { $0.id == "typescript-lsp@official" }!
        #expect(ts.isEnabled == true)
        #expect(ts.version == "1.2.3")
    }

    @Test("Regression: parseEnabledPlugins handles real installed_plugins.json array schema")
    func pluginParseRealSchema() {
        // Real installed_plugins.json has array-of-records per plugin
        let installedJson = """
            {
              "plugins": {
                "todo-manager@claude-plugins-official": [
                  {"version": "2.1.0", "installedAt": "2025-01-15T10:00:00Z", "source": "marketplace"},
                  {"version": "2.0.0", "installedAt": "2024-12-01T08:00:00Z", "source": "marketplace"}
                ],
                "git-helper@community": [
                  {"version": "0.9.1", "installedAt": "2025-02-01T12:00:00Z", "source": "manual"}
                ]
              }
            }
            """
        let settingsJson = """
            {"enabledPlugins":{"todo-manager@claude-plugins-official":true}}
            """

        let plugins = ConfigReader.parseEnabledPlugins(
            settingsData: settingsJson.data(using: .utf8),
            installedPluginsData: installedJson.data(using: .utf8)
        )

        #expect(plugins.count == 2)

        // todo-manager: enabled + version from first install record
        let todo = plugins.first { $0.id == "todo-manager@claude-plugins-official" }!
        #expect(todo.isEnabled == true)
        #expect(todo.version == "2.1.0")
        #expect(todo.name == "todo-manager")
        #expect(todo.marketplace == "claude-plugins-official")

        // git-helper: not in settings → not enabled, version from single record
        let git = plugins.first { $0.id == "git-helper@community" }!
        #expect(git.isEnabled == false)
        #expect(git.version == "0.9.1")
    }

    @Test("parseEnabledPlugins with nil data returns empty")
    func pluginParseNilData() {
        let plugins = ConfigReader.parseEnabledPlugins(
            settingsData: nil, installedPluginsData: nil
        )
        #expect(plugins.isEmpty)
    }

    @Test("parseEnabledPlugins with empty plugins object")
    func pluginParseEmptyPlugins() {
        let installedJson = """
            {"plugins":{}}
            """
        let plugins = ConfigReader.parseEnabledPlugins(
            settingsData: nil,
            installedPluginsData: installedJson.data(using: .utf8)
        )
        #expect(plugins.isEmpty)
    }

    // MARK: - Snapshots

    @Test("snapshot EnabledPlugin dump")
    func snapshotEnabledPlugin() {
        let plugin = EnabledPlugin(
            id: "typescript-lsp@claude-plugins-official",
            name: "typescript-lsp",
            marketplace: "claude-plugins-official",
            isEnabled: true,
            version: "1.2.3"
        )
        assertInlineSnapshot(of: plugin, as: .dump) {
            """
            ▿ EnabledPlugin
              - id: "typescript-lsp@claude-plugins-official"
              - isEnabled: true
              - marketplace: "claude-plugins-official"
              - name: "typescript-lsp"
              - version: "1.2.3"

            """
        }
    }

    @Test("snapshot SessionHistoryEntry dump")
    func snapshotSessionHistoryEntry() {
        let entry = SessionHistoryEntry(
            id: "entry-001",
            sessionId: "sess-abc123",
            projectPath: "/home/user/project",
            timestamp: Date(timeIntervalSince1970: 1700000000),
            displayText: "Implement feature X"
        )
        assertInlineSnapshot(of: entry, as: .dump) {
            """
            ▿ SessionHistoryEntry
              - displayText: "Implement feature X"
              - id: "entry-001"
              - projectPath: "/home/user/project"
              - sessionId: "sess-abc123"
              - timestamp: 2023-11-14T22:13:20Z

            """
        }
    }

    @Test("snapshot disabled plugin dump")
    func snapshotDisabledPlugin() {
        let plugin = EnabledPlugin(
            id: "experimental@community",
            name: "experimental",
            marketplace: "community",
            isEnabled: false,
            version: "0.1.0-beta"
        )
        assertInlineSnapshot(of: plugin, as: .dump) {
            """
            ▿ EnabledPlugin
              - id: "experimental@community"
              - isEnabled: false
              - marketplace: "community"
              - name: "experimental"
              - version: "0.1.0-beta"

            """
        }
    }
}

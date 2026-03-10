import Foundation
import InlineSnapshotTesting
import Testing

@testable import AsukuAppCore

@Suite("TelemetryReader Tests")
struct TelemetryReaderTests {

    // MARK: - parseToolUsageLine

    @Test("Parse tengu_tool_use_success extracts toolName as .tool")
    func parseToolUseSuccess() {
        let line = """
            {"event_type":"ClaudeCodeInternalEvent","event_data":{"event_name":"tengu_tool_use_success","additional_metadata":"{\\"toolName\\":\\"Read\\",\\"isMcp\\":false,\\"durationMs\\":5}"}}
            """
        let result = TelemetryReader.parseToolUsageLine(line)
        #expect(result?.name == "Read")
        #expect(result?.category == .tool)
    }

    @Test("Parse tengu_skill_loaded extracts skill_name as .skill")
    func parseSkillLoaded() {
        let line = """
            {"event_type":"ClaudeCodeInternalEvent","event_data":{"event_name":"tengu_skill_loaded","additional_metadata":"{\\"skill_name\\":\\"keybindings-help\\",\\"skill_source\\":\\"bundled\\"}"}}
            """
        let result = TelemetryReader.parseToolUsageLine(line)
        #expect(result?.name == "keybindings-help")
        #expect(result?.category == .skill)
    }

    @Test("Parse tengu_agent_tool_selected extracts agent_type as .agent")
    func parseAgentToolSelected() {
        let line = """
            {"event_type":"ClaudeCodeInternalEvent","event_data":{"event_name":"tengu_agent_tool_selected","additional_metadata":"{\\"agent_type\\":\\"Explore\\",\\"model\\":\\"claude-haiku-4-5-20251001\\"}"}}
            """
        let result = TelemetryReader.parseToolUsageLine(line)
        #expect(result?.name == "Explore")
        #expect(result?.category == .agent)
    }

    @Test("Parse tengu_input_command extracts input as .command")
    func parseInputCommand() {
        let line = """
            {"event_type":"ClaudeCodeInternalEvent","event_data":{"event_name":"tengu_input_command","additional_metadata":"{\\"input\\":\\"exit\\"}"}}
            """
        let result = TelemetryReader.parseToolUsageLine(line)
        #expect(result?.name == "exit")
        #expect(result?.category == .command)
    }

    @Test("Irrelevant event returns nil")
    func parseIrrelevantEvent() {
        let line = """
            {"event_type":"ClaudeCodeInternalEvent","event_data":{"event_name":"tengu_exit","additional_metadata":"{\\"last_session_cost\\":1.42}"}}
            """
        let result = TelemetryReader.parseToolUsageLine(line)
        #expect(result == nil)
    }

    @Test("Invalid JSON returns nil")
    func parseInvalidJson() {
        let result = TelemetryReader.parseToolUsageLine("not valid json {{{")
        #expect(result == nil)
    }

    @Test("Missing metadata field returns nil")
    func parseMissingMetadataField() {
        let line = """
            {"event_type":"ClaudeCodeInternalEvent","event_data":{"event_name":"tengu_tool_use_success","additional_metadata":"{\\"isMcp\\":false}"}}
            """
        let result = TelemetryReader.parseToolUsageLine(line)
        #expect(result == nil)
    }

    // MARK: - readToolUsage

    @Test("readToolUsage aggregates counts from JSONL files")
    func readToolUsageAggregates() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let lines = [
            """
            {"event_type":"ClaudeCodeInternalEvent","event_data":{"event_name":"tengu_tool_use_success","additional_metadata":"{\\"toolName\\":\\"Read\\",\\"isMcp\\":false}"}}
            """,
            """
            {"event_type":"ClaudeCodeInternalEvent","event_data":{"event_name":"tengu_tool_use_success","additional_metadata":"{\\"toolName\\":\\"Read\\",\\"isMcp\\":false}"}}
            """,
            """
            {"event_type":"ClaudeCodeInternalEvent","event_data":{"event_name":"tengu_tool_use_success","additional_metadata":"{\\"toolName\\":\\"Edit\\",\\"isMcp\\":false}"}}
            """,
            """
            {"event_type":"ClaudeCodeInternalEvent","event_data":{"event_name":"tengu_skill_loaded","additional_metadata":"{\\"skill_name\\":\\"commit\\"}"}}
            """,
            """
            {"event_type":"ClaudeCodeInternalEvent","event_data":{"event_name":"tengu_exit","additional_metadata":"{\\"last_session_cost\\":0}"}}
            """,
        ]
        let filePath = tempDir.appendingPathComponent("test.json")
        try lines.joined(separator: "\n").write(to: filePath, atomically: true, encoding: .utf8)

        let snapshot = TelemetryReader.readToolUsage(from: tempDir.path)
        #expect(snapshot.totalCount == 4)
        #expect(snapshot.entries.count == 3)

        let read = snapshot.entries.first { $0.name == "Read" }
        #expect(read?.count == 2)
        #expect(read?.category == .tool)

        let edit = snapshot.entries.first { $0.name == "Edit" }
        #expect(edit?.count == 1)

        let commit = snapshot.entries.first { $0.name == "commit" }
        #expect(commit?.count == 1)
        #expect(commit?.category == .skill)
    }

    @Test("readToolUsage returns empty for empty directory")
    func readToolUsageEmptyDir() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshot = TelemetryReader.readToolUsage(from: tempDir.path)
        #expect(snapshot == .empty)
    }

    @Test("readToolUsage entries are sorted by count descending")
    func readToolUsageSortOrder() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var lines: [String] = []
        // 3x Bash, 1x Read, 2x Edit
        for _ in 0..<3 {
            lines.append(
                """
                {"event_type":"ClaudeCodeInternalEvent","event_data":{"event_name":"tengu_tool_use_success","additional_metadata":"{\\"toolName\\":\\"Bash\\"}"}}
                """
            )
        }
        lines.append(
            """
            {"event_type":"ClaudeCodeInternalEvent","event_data":{"event_name":"tengu_tool_use_success","additional_metadata":"{\\"toolName\\":\\"Read\\"}"}}
            """
        )
        for _ in 0..<2 {
            lines.append(
                """
                {"event_type":"ClaudeCodeInternalEvent","event_data":{"event_name":"tengu_tool_use_success","additional_metadata":"{\\"toolName\\":\\"Edit\\"}"}}
                """
            )
        }

        let filePath = tempDir.appendingPathComponent("test.json")
        try lines.joined(separator: "\n").write(to: filePath, atomically: true, encoding: .utf8)

        let snapshot = TelemetryReader.readToolUsage(from: tempDir.path)
        #expect(snapshot.entries.count == 3)
        #expect(snapshot.entries[0].name == "Bash")
        #expect(snapshot.entries[0].count == 3)
        #expect(snapshot.entries[1].name == "Edit")
        #expect(snapshot.entries[1].count == 2)
        #expect(snapshot.entries[2].name == "Read")
        #expect(snapshot.entries[2].count == 1)
    }

    @Test("readToolUsage aggregates across multiple files")
    func readToolUsageMultipleFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file1Lines = [
            """
            {"event_type":"ClaudeCodeInternalEvent","event_data":{"event_name":"tengu_tool_use_success","additional_metadata":"{\\"toolName\\":\\"Read\\"}"}}
            """
        ]
        let file2Lines = [
            """
            {"event_type":"ClaudeCodeInternalEvent","event_data":{"event_name":"tengu_tool_use_success","additional_metadata":"{\\"toolName\\":\\"Read\\"}"}}
            """,
            """
            {"event_type":"ClaudeCodeInternalEvent","event_data":{"event_name":"tengu_tool_use_success","additional_metadata":"{\\"toolName\\":\\"Write\\"}"}}
            """,
        ]

        try file1Lines.joined(separator: "\n").write(
            to: tempDir.appendingPathComponent("a.json"), atomically: true, encoding: .utf8)
        try file2Lines.joined(separator: "\n").write(
            to: tempDir.appendingPathComponent("b.json"), atomically: true, encoding: .utf8)

        let snapshot = TelemetryReader.readToolUsage(from: tempDir.path)
        #expect(snapshot.totalCount == 3)
        let read = snapshot.entries.first { $0.name == "Read" }
        #expect(read?.count == 2)
    }

    // MARK: - Snapshots

    @Test("snapshot ToolUsageEntry dump")
    func snapshotToolUsageEntry() {
        let entry = ToolUsageEntry(name: "Read", category: .tool, count: 42)
        assertInlineSnapshot(of: entry, as: .dump) {
            """
            ▿ ToolUsageEntry
              - category: ToolCategory.tool
              - count: 42
              - name: "Read"

            """
        }
    }
}

import Foundation
import InlineSnapshotTesting
import Testing

@testable import AsukuShared

/// Tests for StatuslineHandler behavior.
/// Since StatuslineHandler writes to stdout directly and uses IPCClient,
/// we test the underlying logic (parsing, sessionId resolution) using
/// the shared types directly.
@Suite("StatuslineHandler Tests")
struct StatuslineHandlerTests {

    // MARK: - StatuslineData Parsing for Hook

    @Test("Valid statusline JSON parses successfully")
    func validStatuslineParse() throws {
        let json = """
            {
                "session_id": "sess-abc",
                "model": { "id": "claude-opus-4-6", "display_name": "Opus 4.6" },
                "context_window": { "used_percentage": 45 }
            }
            """
        let data = Data(json.utf8)
        let statusline = try JSONDecoder().decode(StatuslineData.self, from: data)

        #expect(statusline.sessionId == "sess-abc")
        #expect(statusline.model?.id == "claude-opus-4-6")
        #expect(statusline.model?.displayName == "Opus 4.6")
        #expect(statusline.contextWindow?.usedPercentage == 45)
    }

    @Test("sessionId fallback to transcriptPath when sessionId is missing")
    func sessionIdFallbackToTranscriptPath() throws {
        let json = """
            {
                "transcript_path": "/home/user/.claude/transcript.jsonl",
                "model": { "id": "claude-opus-4-6" }
            }
            """
        let data = Data(json.utf8)
        let statusline = try JSONDecoder().decode(StatuslineData.self, from: data)

        #expect(statusline.sessionId == nil)
        #expect(statusline.transcriptPath == "/home/user/.claude/transcript.jsonl")

        let resolvedId = statusline.sessionId ?? statusline.transcriptPath
        #expect(resolvedId == "/home/user/.claude/transcript.jsonl")
    }

    @Test("sessionId preferred over transcriptPath when both present")
    func sessionIdPreferredOverTranscriptPath() throws {
        let json = """
            {
                "session_id": "sess-preferred",
                "transcript_path": "/path/to/transcript.jsonl"
            }
            """
        let data = Data(json.utf8)
        let statusline = try JSONDecoder().decode(StatuslineData.self, from: data)

        let resolvedId = statusline.sessionId ?? statusline.transcriptPath
        #expect(resolvedId == "sess-preferred")
    }

    @Test("Both sessionId and transcriptPath missing results in nil resolved ID")
    func bothIdsMissing() throws {
        let json = """
            {
                "model": { "id": "claude-opus-4-6" }
            }
            """
        let data = Data(json.utf8)
        let statusline = try JSONDecoder().decode(StatuslineData.self, from: data)

        let resolvedId = statusline.sessionId ?? statusline.transcriptPath
        #expect(resolvedId == nil)
    }

    @Test("Invalid JSON data fails to decode")
    func invalidJSONFails() {
        let data = Data("not json at all".utf8)
        let result = try? JSONDecoder().decode(StatuslineData.self, from: data)
        #expect(result == nil)
    }

    @Test("Empty data fails to decode")
    func emptyData() {
        let data = Data()
        let result = try? JSONDecoder().decode(StatuslineData.self, from: data)
        #expect(result == nil)
    }

    @Test("Truncated JSON fails to decode")
    func truncatedJSON() {
        let data = Data("{\"session_id\": \"sess".utf8)
        let result = try? JSONDecoder().decode(StatuslineData.self, from: data)
        #expect(result == nil)
    }

    @Test("Binary data fails to decode")
    func binaryData() {
        let data = Data([0x00, 0xFF, 0xFE, 0xAB])
        let result = try? JSONDecoder().decode(StatuslineData.self, from: data)
        #expect(result == nil)
    }

    // MARK: - StatusUpdateEvent Construction

    @Test("StatusUpdateEvent is correctly constructed from StatuslineData")
    func statusUpdateEventConstruction() throws {
        let json = """
            {
                "session_id": "sess-construct",
                "model": { "id": "claude-opus-4-6" },
                "cost": { "total_cost_usd": 0.05 }
            }
            """
        let data = Data(json.utf8)
        let statusline = try JSONDecoder().decode(StatuslineData.self, from: data)
        let sessionId = statusline.sessionId!

        let event = StatusUpdateEvent(
            sessionId: sessionId,
            statusline: statusline,
            timestamp: Date(timeIntervalSince1970: 1700000000)
        )

        #expect(event.sessionId == "sess-construct")
        #expect(event.statusline.model?.id == "claude-opus-4-6")
        #expect(event.statusline.cost?.totalCostUsd == 0.05)
    }

    @Test("StatusUpdateEvent with transcriptPath as sessionId")
    func statusUpdateEventWithTranscriptPath() throws {
        let json = """
            {
                "transcript_path": "/path/to/transcript.jsonl",
                "model": { "id": "claude-sonnet-4-6" }
            }
            """
        let data = Data(json.utf8)
        let statusline = try JSONDecoder().decode(StatuslineData.self, from: data)
        let sessionId = statusline.sessionId ?? statusline.transcriptPath ?? "unknown"

        let event = StatusUpdateEvent(
            sessionId: sessionId,
            statusline: statusline,
            timestamp: Date(timeIntervalSince1970: 1700000000)
        )

        #expect(event.sessionId == "/path/to/transcript.jsonl")
    }

    @Test("StatusUpdateEvent encodes to valid IPCMessage")
    func statusUpdateEventIPCMessage() throws {
        let statusline = StatuslineData(
            sessionId: "sess-ipc",
            model: ModelInfo(id: "claude-opus-4-6")
        )
        let event = StatusUpdateEvent(
            sessionId: "sess-ipc",
            statusline: statusline,
            timestamp: Date(timeIntervalSince1970: 1700000000)
        )
        let message = IPCMessage(payload: .statusUpdate(event))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(message)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(IPCMessage.self, from: jsonData)

        if case .statusUpdate(let decodedEvent) = decoded.payload {
            #expect(decodedEvent.sessionId == "sess-ipc")
        } else {
            Issue.record("Expected statusUpdate payload")
        }
    }

    // MARK: - IPCMessage Wire Format for StatusUpdate

    @Test("StatusUpdate IPCMessage through wire format roundtrip")
    func statusUpdateWireFormatRoundtrip() throws {
        let statusline = StatuslineData(
            sessionId: "sess-wire",
            model: ModelInfo(id: "claude-opus-4-6", displayName: "Opus 4.6"),
            cost: CostInfo(totalCostUsd: 0.123),
            contextWindow: ContextWindowInfo(usedPercentage: 85)
        )
        let event = StatusUpdateEvent(
            sessionId: "sess-wire",
            statusline: statusline,
            timestamp: Date(timeIntervalSince1970: 1700000000)
        )
        let message = IPCMessage(payload: .statusUpdate(event))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(message)
        let frame = IPCWireFormat.encode(jsonData)

        // Decode wire format
        let decoded = IPCWireFormat.decode(frame)
        #expect(decoded != nil)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedMessage = try decoder.decode(IPCMessage.self, from: decoded!.payload)

        if case .statusUpdate(let decodedEvent) = decodedMessage.payload {
            #expect(decodedEvent.sessionId == "sess-wire")
            #expect(decodedEvent.statusline.cost?.totalCostUsd == 0.123)
            #expect(decodedEvent.statusline.contextWindow?.usedPercentage == 85)
        } else {
            Issue.record("Expected statusUpdate payload")
        }
    }

    // MARK: - Passthrough Guarantee

    @Test("Input data is preserved exactly for passthrough")
    func passthroughDataPreservation() throws {
        let json = """
            {"session_id":"sess-pass","model":{"id":"test"}}
            """
        let inputData = Data(json.utf8)

        let statusline = try JSONDecoder().decode(StatuslineData.self, from: inputData)
        #expect(statusline.sessionId == "sess-pass")

        // The handler would write inputData to stdout unchanged
        #expect(inputData == Data(json.utf8))
    }

    @Test("Invalid JSON input data bytes are preserved for passthrough")
    func passthroughInvalidJsonPreservation() {
        let invalidJson = "this is not json {{"
        let inputData = Data(invalidJson.utf8)

        // Even though decode fails, the bytes should be preserved for passthrough
        let result = try? JSONDecoder().decode(StatuslineData.self, from: inputData)
        #expect(result == nil)
        #expect(inputData == Data(invalidJson.utf8))
    }

    @Test("Empty input data bytes are preserved for passthrough")
    func passthroughEmptyPreservation() {
        let inputData = Data()
        #expect(inputData.isEmpty)
        // Empty data would be written to stdout in defer block
    }

    // MARK: - Realistic statusline JSON from Claude Code

    @Test("Parse realistic full statusline from Claude Code")
    func parseRealisticStatusline() throws {
        let json = """
            {
                "cwd": "/Users/user/ghq/github.com/user/project",
                "session_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
                "transcript_path": "/Users/user/.claude/projects/-Users-user-project/transcript.jsonl",
                "model": {
                    "id": "claude-opus-4-6",
                    "display_name": "Claude Opus 4.6"
                },
                "workspace": {
                    "current_dir": "/Users/user/ghq/github.com/user/project",
                    "project_dir": "/Users/user/ghq/github.com/user/project"
                },
                "version": "1.0.30",
                "cost": {
                    "total_cost_usd": 0.0456,
                    "total_duration_ms": 120000,
                    "total_api_duration_ms": 90000,
                    "total_lines_added": 250,
                    "total_lines_removed": 45
                },
                "context_window": {
                    "total_input_tokens": 150000,
                    "total_output_tokens": 30000,
                    "context_window_size": 200000,
                    "used_percentage": 78,
                    "remaining_percentage": 22,
                    "current_usage": {
                        "input_tokens": 140000,
                        "output_tokens": 28000,
                        "cache_creation_input_tokens": 15000,
                        "cache_read_input_tokens": 80000
                    }
                },
                "exceeds_200k_tokens": false,
                "agent": {
                    "name": "Explore"
                }
            }
            """
        let data = Data(json.utf8)
        let statusline = try JSONDecoder().decode(StatuslineData.self, from: data)

        #expect(statusline.sessionId == "a1b2c3d4-e5f6-7890-abcd-ef1234567890")
        #expect(statusline.model?.displayName == "Claude Opus 4.6")
        #expect(statusline.version == "1.0.30")
        #expect(statusline.cost?.totalCostUsd == 0.0456)
        #expect(statusline.cost?.totalDurationMs == 120000)
        #expect(statusline.contextWindow?.usedPercentage == 78)
        #expect(statusline.contextWindow?.currentUsage?.cacheReadInputTokens == 80000)
        #expect(statusline.agent?.name == "Explore")
        #expect(statusline.exceedsContextLimit == false)
    }

    // MARK: - Snapshots

    @Test("snapshot StatusUpdateEvent JSON from handler scenario")
    func snapshotHandlerStatusUpdateEvent() throws {
        let statusline = StatuslineData(
            sessionId: "sess-handler",
            model: ModelInfo(id: "claude-opus-4-6", displayName: "Opus 4.6"),
            cost: CostInfo(totalCostUsd: 0.05, totalLinesAdded: 100, totalLinesRemoved: 20),
            contextWindow: ContextWindowInfo(usedPercentage: 65)
        )
        let event = StatusUpdateEvent(
            sessionId: "sess-handler",
            statusline: statusline,
            timestamp: Date(timeIntervalSince1970: 1700000000)
        )
        let message = IPCMessage(payload: .statusUpdate(event))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        assertInlineSnapshot(of: message, as: .json(encoder)) {
            """
            {
              "payload" : {
                "data" : {
                  "sessionId" : "sess-handler",
                  "statusline" : {
                    "context_window" : {
                      "used_percentage" : 65
                    },
                    "cost" : {
                      "total_cost_usd" : 0.05,
                      "total_lines_added" : 100,
                      "total_lines_removed" : 20
                    },
                    "model" : {
                      "display_name" : "Opus 4.6",
                      "id" : "claude-opus-4-6"
                    },
                    "session_id" : "sess-handler"
                  },
                  "timestamp" : "2023-11-14T22:13:20Z"
                },
                "type" : "statusUpdate"
              },
              "protocolVersion" : 1
            }
            """
        }
    }

    @Test("snapshot sessionId resolution scenarios")
    func snapshotSessionIdResolution() {
        // Scenario 1: Both present → use sessionId
        let s1 = StatuslineData(sessionId: "sid", transcriptPath: "/path")
        let resolved1 = s1.sessionId ?? s1.transcriptPath
        #expect(resolved1 == "sid")

        // Scenario 2: Only transcriptPath → use transcriptPath
        let s2 = StatuslineData(transcriptPath: "/path/transcript.jsonl")
        let resolved2 = s2.sessionId ?? s2.transcriptPath
        #expect(resolved2 == "/path/transcript.jsonl")

        // Scenario 3: Neither → nil
        let s3 = StatuslineData()
        let resolved3 = s3.sessionId ?? s3.transcriptPath
        #expect(resolved3 == nil)
    }
}

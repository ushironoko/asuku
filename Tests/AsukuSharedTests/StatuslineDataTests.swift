import Foundation
import InlineSnapshotTesting
import Testing

@testable import AsukuShared

@Suite("StatuslineData Tests")
struct StatuslineDataTests {

    // MARK: - Full JSON Decode

    @Test("Decode full statusline JSON with all fields")
    func decodeFullJSON() throws {
        let json = """
            {
                "cwd": "/home/user/project",
                "session_id": "sess-abc123",
                "transcript_path": "/home/user/.claude/transcript.jsonl",
                "model": {
                    "id": "claude-opus-4-6",
                    "display_name": "Opus 4.6"
                },
                "workspace": {
                    "current_dir": "/home/user/project",
                    "project_dir": "/home/user/project"
                },
                "version": "1.0.30",
                "cost": {
                    "total_cost_usd": 0.0123,
                    "total_duration_ms": 45000,
                    "total_api_duration_ms": 30000,
                    "total_lines_added": 156,
                    "total_lines_removed": 23
                },
                "context_window": {
                    "total_input_tokens": 50000,
                    "total_output_tokens": 10000,
                    "context_window_size": 200000,
                    "used_percentage": 78,
                    "remaining_percentage": 22,
                    "current_usage": {
                        "input_tokens": 48000,
                        "output_tokens": 9500,
                        "cache_creation_input_tokens": 5000,
                        "cache_read_input_tokens": 20000
                    }
                },
                "exceeds_200k_tokens": false,
                "agent": {
                    "name": "task-agent"
                }
            }
            """
        let data = Data(json.utf8)
        let statusline = try JSONDecoder().decode(StatuslineData.self, from: data)

        #expect(statusline.cwd == "/home/user/project")
        #expect(statusline.sessionId == "sess-abc123")
        #expect(statusline.transcriptPath == "/home/user/.claude/transcript.jsonl")
        #expect(statusline.model?.id == "claude-opus-4-6")
        #expect(statusline.model?.displayName == "Opus 4.6")
        #expect(statusline.workspace?.currentDir == "/home/user/project")
        #expect(statusline.workspace?.projectDir == "/home/user/project")
        #expect(statusline.version == "1.0.30")
        #expect(statusline.cost?.totalCostUsd == 0.0123)
        #expect(statusline.cost?.totalDurationMs == 45000)
        #expect(statusline.cost?.totalApiDurationMs == 30000)
        #expect(statusline.cost?.totalLinesAdded == 156)
        #expect(statusline.cost?.totalLinesRemoved == 23)
        #expect(statusline.contextWindow?.totalInputTokens == 50000)
        #expect(statusline.contextWindow?.totalOutputTokens == 10000)
        #expect(statusline.contextWindow?.contextWindowSize == 200000)
        #expect(statusline.contextWindow?.usedPercentage == 78)
        #expect(statusline.contextWindow?.remainingPercentage == 22)
        #expect(statusline.contextWindow?.currentUsage?.inputTokens == 48000)
        #expect(statusline.contextWindow?.currentUsage?.outputTokens == 9500)
        #expect(statusline.contextWindow?.currentUsage?.cacheCreationInputTokens == 5000)
        #expect(statusline.contextWindow?.currentUsage?.cacheReadInputTokens == 20000)
        #expect(statusline.exceedsContextLimit == false)
        #expect(statusline.agent?.name == "task-agent")
    }

    @Test("Decode partial JSON with missing optional fields")
    func decodePartialJSON() throws {
        let json = """
            {
                "session_id": "sess-123",
                "model": {
                    "id": "claude-sonnet-4-6"
                },
                "context_window": {
                    "used_percentage": 45
                }
            }
            """
        let data = Data(json.utf8)
        let statusline = try JSONDecoder().decode(StatuslineData.self, from: data)

        #expect(statusline.sessionId == "sess-123")
        #expect(statusline.model?.id == "claude-sonnet-4-6")
        #expect(statusline.model?.displayName == nil)
        #expect(statusline.contextWindow?.usedPercentage == 45)
        #expect(statusline.contextWindow?.contextWindowSize == nil)
        #expect(statusline.cwd == nil)
        #expect(statusline.cost == nil)
        #expect(statusline.agent == nil)
    }

    @Test("Decode empty JSON object results in all nil fields")
    func decodeEmptyJSON() throws {
        let json = "{}"
        let data = Data(json.utf8)
        let statusline = try JSONDecoder().decode(StatuslineData.self, from: data)

        #expect(statusline.cwd == nil)
        #expect(statusline.sessionId == nil)
        #expect(statusline.transcriptPath == nil)
        #expect(statusline.model == nil)
        #expect(statusline.workspace == nil)
        #expect(statusline.version == nil)
        #expect(statusline.cost == nil)
        #expect(statusline.contextWindow == nil)
        #expect(statusline.exceedsContextLimit == nil)
        #expect(statusline.agent == nil)
    }

    // MARK: - StatusUpdateEvent Roundtrip

    @Test("StatusUpdateEvent encode/decode roundtrip")
    func statusUpdateEventRoundtrip() throws {
        let statusline = StatuslineData(
            sessionId: "sess-rt",
            model: ModelInfo(id: "claude-opus-4-6", displayName: "Opus 4.6"),
            contextWindow: ContextWindowInfo(usedPercentage: 50)
        )
        let event = StatusUpdateEvent(
            sessionId: "sess-rt",
            statusline: statusline,
            timestamp: Date(timeIntervalSince1970: 1700000000)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StatusUpdateEvent.self, from: data)

        #expect(decoded.sessionId == "sess-rt")
        #expect(decoded.statusline.model?.id == "claude-opus-4-6")
        #expect(decoded.statusline.contextWindow?.usedPercentage == 50)
    }

    // MARK: - IPCMessage with StatusUpdate

    @Test("IPCMessage with statusUpdate wire format")
    func ipcMessageStatusUpdate() throws {
        let statusline = StatuslineData(
            sessionId: "sess-wire",
            model: ModelInfo(id: "claude-opus-4-6")
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

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(IPCMessage.self, from: jsonData)

        if case .statusUpdate(let decodedEvent) = decoded.payload {
            #expect(decodedEvent.sessionId == "sess-wire")
            #expect(decodedEvent.statusline.model?.id == "claude-opus-4-6")
        } else {
            Issue.record("Expected statusUpdate payload")
        }
    }

    // MARK: - Unknown Payload Type

    @Test("Unknown payload type decodes to .unknown")
    func unknownPayloadDecode() throws {
        let json = """
            {
                "protocolVersion": 1,
                "payload": {
                    "type": "future_feature",
                    "data": {}
                }
            }
            """
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        let message = try decoder.decode(IPCMessage.self, from: data)

        if case .unknown(let typeString) = message.payload {
            #expect(typeString == "future_feature")
        } else {
            Issue.record("Expected unknown payload")
        }
    }

    @Test("Unknown payload type encodes correctly")
    func unknownPayloadEncode() throws {
        let message = IPCMessage(payload: .unknown("future_feature"))

        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let payload = json["payload"] as! [String: Any]

        #expect(payload["type"] as? String == "future_feature")
    }

    // MARK: - Sub-struct Isolation Tests

    @Test("ModelInfo with only id, no displayName")
    func modelInfoIdOnly() throws {
        let json = """
            {"id": "claude-haiku-4-5"}
            """
        let model = try JSONDecoder().decode(ModelInfo.self, from: Data(json.utf8))
        #expect(model.id == "claude-haiku-4-5")
        #expect(model.displayName == nil)
    }

    @Test("ModelInfo with both id and displayName")
    func modelInfoFull() throws {
        let json = """
            {"id": "claude-opus-4-6", "display_name": "Opus 4.6"}
            """
        let model = try JSONDecoder().decode(ModelInfo.self, from: Data(json.utf8))
        #expect(model.id == "claude-opus-4-6")
        #expect(model.displayName == "Opus 4.6")
    }

    @Test("WorkspaceInfo with only currentDir")
    func workspaceCurrentDirOnly() throws {
        let json = """
            {"current_dir": "/home/user"}
            """
        let ws = try JSONDecoder().decode(WorkspaceInfo.self, from: Data(json.utf8))
        #expect(ws.currentDir == "/home/user")
        #expect(ws.projectDir == nil)
    }

    @Test("WorkspaceInfo with only projectDir")
    func workspaceProjectDirOnly() throws {
        let json = """
            {"project_dir": "/home/user/project"}
            """
        let ws = try JSONDecoder().decode(WorkspaceInfo.self, from: Data(json.utf8))
        #expect(ws.currentDir == nil)
        #expect(ws.projectDir == "/home/user/project")
    }

    @Test("CostInfo with only totalCostUsd")
    func costInfoPartial() throws {
        let json = """
            {"total_cost_usd": 1.234}
            """
        let cost = try JSONDecoder().decode(CostInfo.self, from: Data(json.utf8))
        #expect(cost.totalCostUsd == 1.234)
        #expect(cost.totalDurationMs == nil)
        #expect(cost.totalApiDurationMs == nil)
        #expect(cost.totalLinesAdded == nil)
        #expect(cost.totalLinesRemoved == nil)
    }

    @Test("CostInfo with only line counts")
    func costInfoLinesOnly() throws {
        let json = """
            {"total_lines_added": 500, "total_lines_removed": 100}
            """
        let cost = try JSONDecoder().decode(CostInfo.self, from: Data(json.utf8))
        #expect(cost.totalCostUsd == nil)
        #expect(cost.totalLinesAdded == 500)
        #expect(cost.totalLinesRemoved == 100)
    }

    @Test("ContextWindowInfo with only size and percentage")
    func contextWindowPartial() throws {
        let json = """
            {"context_window_size": 200000, "used_percentage": 95, "remaining_percentage": 5}
            """
        let cw = try JSONDecoder().decode(ContextWindowInfo.self, from: Data(json.utf8))
        #expect(cw.contextWindowSize == 200000)
        #expect(cw.usedPercentage == 95)
        #expect(cw.remainingPercentage == 5)
        #expect(cw.totalInputTokens == nil)
        #expect(cw.currentUsage == nil)
    }

    @Test("TokenUsage with all cache fields")
    func tokenUsageFull() throws {
        let json = """
            {
                "input_tokens": 100000,
                "output_tokens": 25000,
                "cache_creation_input_tokens": 10000,
                "cache_read_input_tokens": 50000
            }
            """
        let usage = try JSONDecoder().decode(TokenUsage.self, from: Data(json.utf8))
        #expect(usage.inputTokens == 100000)
        #expect(usage.outputTokens == 25000)
        #expect(usage.cacheCreationInputTokens == 10000)
        #expect(usage.cacheReadInputTokens == 50000)
    }

    @Test("TokenUsage with only input/output tokens")
    func tokenUsagePartial() throws {
        let json = """
            {"input_tokens": 5000}
            """
        let usage = try JSONDecoder().decode(TokenUsage.self, from: Data(json.utf8))
        #expect(usage.inputTokens == 5000)
        #expect(usage.outputTokens == nil)
        #expect(usage.cacheCreationInputTokens == nil)
        #expect(usage.cacheReadInputTokens == nil)
    }

    @Test("AgentInfo with nil name")
    func agentInfoNilName() throws {
        let json = """
            {}
            """
        let agent = try JSONDecoder().decode(AgentInfo.self, from: Data(json.utf8))
        #expect(agent.name == nil)
    }

    @Test("AgentInfo with name")
    func agentInfoWithName() throws {
        let json = """
            {"name": "sub-agent-1"}
            """
        let agent = try JSONDecoder().decode(AgentInfo.self, from: Data(json.utf8))
        #expect(agent.name == "sub-agent-1")
    }

    // MARK: - Equatable Tests

    @Test("StatuslineData Equatable with identical values")
    func statuslineDataEquatable() {
        let a = StatuslineData(
            cwd: "/test",
            sessionId: "s1",
            model: ModelInfo(id: "opus", displayName: "Opus")
        )
        let b = StatuslineData(
            cwd: "/test",
            sessionId: "s1",
            model: ModelInfo(id: "opus", displayName: "Opus")
        )
        #expect(a == b)
    }

    @Test("StatuslineData Equatable with different values")
    func statuslineDataNotEqual() {
        let a = StatuslineData(sessionId: "s1")
        let b = StatuslineData(sessionId: "s2")
        #expect(a != b)
    }

    @Test("Two empty StatuslineData are equal")
    func emptyStatuslineDataEqual() {
        let a = StatuslineData()
        let b = StatuslineData()
        #expect(a == b)
    }

    @Test("ModelInfo Equatable")
    func modelInfoEquatable() {
        let a = ModelInfo(id: "opus", displayName: "Opus")
        let b = ModelInfo(id: "opus", displayName: "Opus")
        #expect(a == b)

        let c = ModelInfo(id: "sonnet")
        #expect(a != c)
    }

    @Test("CostInfo Equatable")
    func costInfoEquatable() {
        let a = CostInfo(totalCostUsd: 0.05, totalLinesAdded: 10)
        let b = CostInfo(totalCostUsd: 0.05, totalLinesAdded: 10)
        #expect(a == b)

        let c = CostInfo(totalCostUsd: 0.10)
        #expect(a != c)
    }

    @Test("ContextWindowInfo Equatable")
    func contextWindowInfoEquatable() {
        let a = ContextWindowInfo(usedPercentage: 50, remainingPercentage: 50)
        let b = ContextWindowInfo(usedPercentage: 50, remainingPercentage: 50)
        #expect(a == b)

        let c = ContextWindowInfo(usedPercentage: 80)
        #expect(a != c)
    }

    @Test("TokenUsage Equatable")
    func tokenUsageEquatable() {
        let a = TokenUsage(inputTokens: 100, outputTokens: 50)
        let b = TokenUsage(inputTokens: 100, outputTokens: 50)
        #expect(a == b)

        let c = TokenUsage(inputTokens: 200)
        #expect(a != c)
    }

    // MARK: - Boundary Values

    @Test("CostInfo with zero values")
    func costInfoZeroValues() {
        let cost = CostInfo(totalCostUsd: 0.0, totalLinesAdded: 0, totalLinesRemoved: 0)
        #expect(cost.totalCostUsd == 0.0)
        #expect(cost.totalLinesAdded == 0)
        #expect(cost.totalLinesRemoved == 0)
    }

    @Test("ContextWindow at 0% and 100%")
    func contextWindowBoundaryValues() {
        let zero = ContextWindowInfo(usedPercentage: 0, remainingPercentage: 100)
        #expect(zero.usedPercentage == 0)

        let full = ContextWindowInfo(usedPercentage: 100, remainingPercentage: 0)
        #expect(full.usedPercentage == 100)
    }

    @Test("exceedsContextLimit true")
    func exceedsContextLimitTrue() throws {
        let json = """
            {"exceeds_200k_tokens": true}
            """
        let statusline = try JSONDecoder().decode(StatuslineData.self, from: Data(json.utf8))
        #expect(statusline.exceedsContextLimit == true)
    }

    @Test("StatuslineData with extra unknown fields is tolerant")
    func unknownFieldsTolerant() throws {
        let json = """
            {
                "session_id": "s1",
                "some_future_field": "value",
                "another_new_thing": 42
            }
            """
        let statusline = try JSONDecoder().decode(StatuslineData.self, from: Data(json.utf8))
        #expect(statusline.sessionId == "s1")
    }

    // MARK: - Encode/Decode Roundtrip for sub-structs

    @Test("ModelInfo encode/decode roundtrip")
    func modelInfoRoundtrip() throws {
        let original = ModelInfo(id: "claude-opus-4-6", displayName: "Opus 4.6")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ModelInfo.self, from: data)
        #expect(original == decoded)
    }

    @Test("WorkspaceInfo encode/decode roundtrip")
    func workspaceInfoRoundtrip() throws {
        let original = WorkspaceInfo(currentDir: "/a", projectDir: "/b")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkspaceInfo.self, from: data)
        #expect(original == decoded)
    }

    @Test("CostInfo encode/decode roundtrip")
    func costInfoRoundtrip() throws {
        let original = CostInfo(
            totalCostUsd: 1.23, totalDurationMs: 5000, totalApiDurationMs: 3000,
            totalLinesAdded: 100, totalLinesRemoved: 50
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CostInfo.self, from: data)
        #expect(original == decoded)
    }

    @Test("ContextWindowInfo encode/decode roundtrip")
    func contextWindowRoundtrip() throws {
        let original = ContextWindowInfo(
            totalInputTokens: 10000, totalOutputTokens: 5000,
            contextWindowSize: 200000, usedPercentage: 75, remainingPercentage: 25,
            currentUsage: TokenUsage(
                inputTokens: 9000, outputTokens: 4500,
                cacheCreationInputTokens: 1000, cacheReadInputTokens: 3000)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ContextWindowInfo.self, from: data)
        #expect(original == decoded)
    }

    @Test("StatuslineData full encode/decode roundtrip preserves all fields")
    func statuslineDataFullRoundtrip() throws {
        let original = StatuslineData(
            cwd: "/home/user",
            sessionId: "sess-rt",
            transcriptPath: "/path/to/transcript.jsonl",
            model: ModelInfo(id: "opus", displayName: "Opus 4.6"),
            workspace: WorkspaceInfo(currentDir: "/a", projectDir: "/b"),
            version: "2.0.0",
            cost: CostInfo(totalCostUsd: 0.5, totalLinesAdded: 10, totalLinesRemoved: 5),
            contextWindow: ContextWindowInfo(usedPercentage: 60),
            exceedsContextLimit: false,
            agent: AgentInfo(name: "agent-1")
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StatuslineData.self, from: data)
        #expect(original == decoded)
    }

    // MARK: - Snapshots

    @Test("snapshot StatuslineData full JSON format")
    func snapshotFullStatuslineData() throws {
        let statusline = StatuslineData(
            cwd: "/home/user/project",
            sessionId: "sess-snap",
            model: ModelInfo(id: "claude-opus-4-6", displayName: "Opus 4.6"),
            workspace: WorkspaceInfo(currentDir: "/home/user/project", projectDir: "/home/user/project"),
            version: "1.0.30",
            cost: CostInfo(totalCostUsd: 0.05, totalLinesAdded: 100, totalLinesRemoved: 20),
            contextWindow: ContextWindowInfo(
                usedPercentage: 78,
                remainingPercentage: 22,
                currentUsage: TokenUsage(inputTokens: 48000, outputTokens: 9500)
            ),
            exceedsContextLimit: false,
            agent: AgentInfo(name: "task-agent")
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        assertInlineSnapshot(of: statusline, as: .json(encoder)) {
            """
            {
              "agent" : {
                "name" : "task-agent"
              },
              "context_window" : {
                "current_usage" : {
                  "input_tokens" : 48000,
                  "output_tokens" : 9500
                },
                "remaining_percentage" : 22,
                "used_percentage" : 78
              },
              "cost" : {
                "total_cost_usd" : 0.05,
                "total_lines_added" : 100,
                "total_lines_removed" : 20
              },
              "cwd" : "\\/home\\/user\\/project",
              "exceeds_200k_tokens" : false,
              "model" : {
                "display_name" : "Opus 4.6",
                "id" : "claude-opus-4-6"
              },
              "session_id" : "sess-snap",
              "version" : "1.0.30",
              "workspace" : {
                "current_dir" : "\\/home\\/user\\/project",
                "project_dir" : "\\/home\\/user\\/project"
              }
            }
            """
        }
    }

    @Test("snapshot empty StatuslineData JSON format")
    func snapshotEmptyStatuslineData() throws {
        let statusline = StatuslineData()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        assertInlineSnapshot(of: statusline, as: .json(encoder)) {
            """
            {

            }
            """
        }
    }

    @Test("snapshot ModelInfo id-only JSON format")
    func snapshotModelInfoIdOnly() throws {
        let model = ModelInfo(id: "claude-haiku-4-5")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        assertInlineSnapshot(of: model, as: .json(encoder)) {
            """
            {
              "id" : "claude-haiku-4-5"
            }
            """
        }
    }

    @Test("snapshot CostInfo partial JSON format")
    func snapshotCostInfoPartial() throws {
        let cost = CostInfo(totalCostUsd: 0.0123, totalLinesAdded: 42)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        assertInlineSnapshot(of: cost, as: .json(encoder)) {
            """
            {
              "total_cost_usd" : 0.0123,
              "total_lines_added" : 42
            }
            """
        }
    }

    @Test("snapshot TokenUsage full JSON format")
    func snapshotTokenUsageFull() throws {
        let usage = TokenUsage(
            inputTokens: 48000, outputTokens: 9500,
            cacheCreationInputTokens: 5000, cacheReadInputTokens: 20000
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        assertInlineSnapshot(of: usage, as: .json(encoder)) {
            """
            {
              "cache_creation_input_tokens" : 5000,
              "cache_read_input_tokens" : 20000,
              "input_tokens" : 48000,
              "output_tokens" : 9500
            }
            """
        }
    }

    @Test("snapshot WorkspaceInfo JSON format")
    func snapshotWorkspaceInfo() throws {
        let ws = WorkspaceInfo(currentDir: "/home/user/project", projectDir: "/home/user/project")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        assertInlineSnapshot(of: ws, as: .json(encoder)) {
            """
            {
              "current_dir" : "\\/home\\/user\\/project",
              "project_dir" : "\\/home\\/user\\/project"
            }
            """
        }
    }

    @Test("snapshot StatusUpdateEvent dump")
    func snapshotStatusUpdateEventDump() throws {
        let event = StatusUpdateEvent(
            sessionId: "sess-dump",
            statusline: StatuslineData(
                model: ModelInfo(id: "opus"),
                cost: CostInfo(totalCostUsd: 0.01)
            ),
            timestamp: Date(timeIntervalSince1970: 1700000000)
        )
        assertInlineSnapshot(of: event, as: .dump) {
            """
            ▿ StatusUpdateEvent
              - sessionId: "sess-dump"
              ▿ statusline: StatuslineData
                - agent: Optional<AgentInfo>.none
                - contextWindow: Optional<ContextWindowInfo>.none
                ▿ cost: Optional<CostInfo>
                  ▿ some: CostInfo
                    - totalApiDurationMs: Optional<Int>.none
                    ▿ totalCostUsd: Optional<Double>
                      - some: 0.01
                    - totalDurationMs: Optional<Int>.none
                    - totalLinesAdded: Optional<Int>.none
                    - totalLinesRemoved: Optional<Int>.none
                - cwd: Optional<String>.none
                - exceedsContextLimit: Optional<Bool>.none
                ▿ model: Optional<ModelInfo>
                  ▿ some: ModelInfo
                    - displayName: Optional<String>.none
                    - id: "opus"
                - sessionId: Optional<String>.none
                - transcriptPath: Optional<String>.none
                - version: Optional<String>.none
                - workspace: Optional<WorkspaceInfo>.none
              - timestamp: 2023-11-14T22:13:20Z

            """
        }
    }

    @Test("snapshot IPCMessage statusUpdate JSON format")
    func snapshotStatusUpdateMessage() throws {
        let statusline = StatuslineData(
            sessionId: "sess-snap-msg",
            model: ModelInfo(id: "claude-opus-4-6")
        )
        let event = StatusUpdateEvent(
            sessionId: "sess-snap-msg",
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
                  "sessionId" : "sess-snap-msg",
                  "statusline" : {
                    "model" : {
                      "id" : "claude-opus-4-6"
                    },
                    "session_id" : "sess-snap-msg"
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
}

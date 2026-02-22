import Foundation
import InlineSnapshotTesting
import Testing

@testable import AsukuShared

@Suite("Handler Tests")
struct HandlerTests {

    // MARK: - HookInput Parsing

    @Test("Parse valid PermissionRequest stdin JSON")
    func parseValidPermissionRequest() throws {
        let json = """
            {
                "session_id": "abc123",
                "transcript_path": "/path/to/transcript.jsonl",
                "cwd": "/path/to/project",
                "permission_mode": "default",
                "hook_event_name": "PermissionRequest",
                "tool_name": "Bash",
                "tool_input": { "command": "rm -rf node_modules" },
                "permission_suggestions": []
            }
            """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(HookInputTestModel.self, from: data)

        #expect(decoded.session_id == "abc123")
        #expect(decoded.hook_event_name == "PermissionRequest")
        #expect(decoded.tool_name == "Bash")
        #expect(decoded.cwd == "/path/to/project")
        #expect(decoded.tool_input["command"]?.stringValue == "rm -rf node_modules")
    }

    @Test("Parse PermissionRequest with complex tool_input")
    func parseComplexToolInput() throws {
        let json = """
            {
                "session_id": "def456",
                "hook_event_name": "PermissionRequest",
                "tool_name": "Write",
                "tool_input": {
                    "file_path": "/tmp/test.txt",
                    "content": "hello world"
                },
                "cwd": "/home/user"
            }
            """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(HookInputTestModel.self, from: data)

        #expect(decoded.tool_name == "Write")
        #expect(decoded.tool_input["file_path"]?.stringValue == "/tmp/test.txt")
        #expect(decoded.tool_input["content"]?.stringValue == "hello world")
    }

    @Test("Invalid JSON throws error")
    func parseInvalidJson() {
        let data = Data("not json".utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(HookInputTestModel.self, from: data)
        }
    }

    @Test("Missing required field throws error")
    func parseMissingField() {
        let json = """
            {
                "session_id": "abc",
                "hook_event_name": "PermissionRequest"
            }
            """
        let data = Data(json.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(HookInputTestModel.self, from: data)
        }
    }

    // MARK: - HookOutput Generation

    @Test("Generate allow response JSON")
    func generateAllowResponse() throws {
        let output = HookOutputTestModel(
            hookSpecificOutput: HookSpecificOutputTestModel(
                hookEventName: "PermissionRequest",
                decision: HookDecisionTestModel(behavior: "allow", message: nil)
            )
        )

        let data = try JSONEncoder().encode(output)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hookOutput = json["hookSpecificOutput"] as! [String: Any]
        let decision = hookOutput["decision"] as! [String: Any]

        #expect(decision["behavior"] as? String == "allow")
    }

    @Test("Generate deny response JSON")
    func generateDenyResponse() throws {
        let output = HookOutputTestModel(
            hookSpecificOutput: HookSpecificOutputTestModel(
                hookEventName: "PermissionRequest",
                decision: HookDecisionTestModel(
                    behavior: "deny",
                    message: "User denied via asuku notification"
                )
            )
        )

        let data = try JSONEncoder().encode(output)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hookOutput = json["hookSpecificOutput"] as! [String: Any]
        let decision = hookOutput["decision"] as! [String: Any]

        #expect(decision["behavior"] as? String == "deny")
        #expect(decision["message"] as? String == "User denied via asuku notification")
    }

    // MARK: - Notification Input Parsing

    @Test("Parse valid Notification stdin JSON")
    func parseNotificationInput() throws {
        let json = """
            {
                "session_id": "sess-1",
                "hook_event_name": "Notification",
                "notification_type": "permission_prompt",
                "message": "Permission needed"
            }
            """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(NotificationInputTestModel.self, from: data)

        #expect(decoded.session_id == "sess-1")
        #expect(decoded.notification_type == "permission_prompt")
        #expect(decoded.message == "Permission needed")
    }

    @Test("Notification with nil optional fields")
    func parseNotificationNilFields() throws {
        let json = """
            {
                "session_id": "sess-2",
                "hook_event_name": "Notification"
            }
            """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(NotificationInputTestModel.self, from: data)

        #expect(decoded.session_id == "sess-2")
        #expect(decoded.notification_type == nil)
        #expect(decoded.message == nil)
        #expect(decoded.title == nil)
    }

    // MARK: - Snapshot: Hook output JSON format

    @Test("snapshot allow output JSON format")
    func snapshotAllowOutput() throws {
        let output = HookOutputTestModel(
            hookSpecificOutput: HookSpecificOutputTestModel(
                hookEventName: "PermissionRequest",
                decision: HookDecisionTestModel(behavior: "allow", message: nil)
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        assertInlineSnapshot(of: output, as: .json(encoder)) {
            """
            {
              "hookSpecificOutput" : {
                "decision" : {
                  "behavior" : "allow"
                },
                "hookEventName" : "PermissionRequest"
              }
            }
            """
        }
    }

    @Test("snapshot deny output JSON format")
    func snapshotDenyOutput() throws {
        let output = HookOutputTestModel(
            hookSpecificOutput: HookSpecificOutputTestModel(
                hookEventName: "PermissionRequest",
                decision: HookDecisionTestModel(
                    behavior: "deny",
                    message: "User denied via asuku notification"
                )
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        assertInlineSnapshot(of: output, as: .json(encoder)) {
            """
            {
              "hookSpecificOutput" : {
                "decision" : {
                  "behavior" : "deny",
                  "message" : "User denied via asuku notification"
                },
                "hookEventName" : "PermissionRequest"
              }
            }
            """
        }
    }

    // MARK: - Snapshot: PermissionRequest input parsed structure

    @Test("snapshot parsed PermissionRequest dump")
    func snapshotParsedInput() throws {
        let json = """
            {
                "session_id": "abc123",
                "hook_event_name": "PermissionRequest",
                "tool_name": "Bash",
                "tool_input": { "command": "echo hello" },
                "cwd": "/tmp"
            }
            """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(HookInputTestModel.self, from: data)

        assertInlineSnapshot(of: decoded, as: .dump) {
            """
            ▿ HookInputTestModel
              - cwd: "/tmp"
              - hook_event_name: "PermissionRequest"
              - permission_mode: Optional<String>.none
              - permission_suggestions: Optional<Array<AnyCodableValue>>.none
              - session_id: "abc123"
              ▿ tool_input: 1 key/value pair
                ▿ (2 elements)
                  - key: "command"
                  ▿ value: echo hello
                    - string: "echo hello"
              - tool_name: "Bash"
              - transcript_path: Optional<String>.none

            """
        }
    }

    // MARK: - IPCClientError descriptions

    @Test("IPCClientError descriptions")
    func ipcClientErrorDescriptions() {
        assertInlineSnapshot(
            of: String(describing: IPCClientErrorTestModel.connectionFailed("refused")), as: .lines
        ) {
            """
            connectionFailed("refused")
            """
        }
        assertInlineSnapshot(
            of: String(describing: IPCClientErrorTestModel.timeout), as: .lines
        ) {
            """
            timeout
            """
        }
        assertInlineSnapshot(
            of: String(describing: IPCClientErrorTestModel.connectionClosed), as: .lines
        ) {
            """
            connectionClosed
            """
        }
    }

    // MARK: - PermissionRequestError description

    @Test("PermissionRequestError description")
    func permissionRequestErrorDescription() {
        let error = PermissionRequestErrorTestModel.requestIdMismatch(
            expected: "req-1", got: "req-2")
        #expect(
            String(describing: error)
                == "requestIdMismatch(expected: \"req-1\", got: \"req-2\")")
    }
}

// MARK: - Test Models (mirror of actual types without importing asuku-hook target)

private struct HookInputTestModel: Codable {
    let session_id: String
    let hook_event_name: String
    let tool_name: String
    let tool_input: [String: AnyCodableValue]
    let cwd: String
    let transcript_path: String?
    let permission_mode: String?
    let permission_suggestions: [AnyCodableValue]?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        session_id = try container.decode(String.self, forKey: .session_id)
        hook_event_name = try container.decode(String.self, forKey: .hook_event_name)
        tool_name = try container.decode(String.self, forKey: .tool_name)
        tool_input = try container.decode(
            [String: AnyCodableValue].self, forKey: .tool_input)
        cwd = try container.decode(String.self, forKey: .cwd)
        transcript_path = try container.decodeIfPresent(String.self, forKey: .transcript_path)
        permission_mode = try container.decodeIfPresent(String.self, forKey: .permission_mode)
        permission_suggestions = try container.decodeIfPresent(
            [AnyCodableValue].self, forKey: .permission_suggestions)
    }
}

private struct HookOutputTestModel: Codable {
    let hookSpecificOutput: HookSpecificOutputTestModel
}

private struct HookSpecificOutputTestModel: Codable {
    let hookEventName: String
    let decision: HookDecisionTestModel
}

private struct HookDecisionTestModel: Codable {
    let behavior: String
    let message: String?
}

private struct NotificationInputTestModel: Codable {
    let session_id: String
    let hook_event_name: String
    let notification_type: String?
    let message: String?
    let title: String?
}

private enum IPCClientErrorTestModel: Error {
    case connectionFailed(String)
    case timeout
    case connectionClosed
    case invalidResponse
}

private enum PermissionRequestErrorTestModel: Error {
    case requestIdMismatch(expected: String, got: String)
}

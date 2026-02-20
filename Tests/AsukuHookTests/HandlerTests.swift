import Foundation
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

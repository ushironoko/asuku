import AsukuShared
import Foundation

/// Claude Code PermissionRequest hook input (stdin JSON)
struct HookInput: Codable {
    let session_id: String
    let hook_event_name: String
    let tool_name: String
    let tool_input: [String: AnyCodableValue]
    let cwd: String
    let transcript_path: String?
    let permission_mode: String?
    let permission_suggestions: [AnyCodableValue]?
}

/// Claude Code PermissionRequest hook output (stdout JSON)
struct HookOutput: Codable {
    let hookSpecificOutput: HookSpecificOutput
}

struct HookSpecificOutput: Codable {
    let hookEventName: String
    let decision: HookDecision
}

struct HookDecision: Codable {
    let behavior: String
    let message: String?
}

enum PermissionRequestHandler {
    static func handle(inputData: Data) throws {
        let decoder = JSONDecoder()
        let input = try decoder.decode(HookInput.self, from: inputData)

        let requestId = UUID().uuidString
        let event = PermissionRequestEvent(
            requestId: requestId,
            sessionId: input.session_id,
            toolName: input.tool_name,
            toolInput: input.tool_input,
            cwd: input.cwd
        )

        let message = IPCMessage(payload: .permissionRequest(event))

        // Send to asuku app and wait for response
        let responseData = try IPCClient.sendAndReceive(message)

        let responseDecoder = JSONDecoder()
        responseDecoder.dateDecodingStrategy = .iso8601
        let response = try responseDecoder.decode(IPCResponse.self, from: responseData)

        // Verify requestId correlation
        guard response.requestId == requestId else {
            throw PermissionRequestError.requestIdMismatch(
                expected: requestId, got: response.requestId)
        }

        // Build Claude Code compatible output
        let output: HookOutput
        switch response.decision {
        case .allow:
            output = HookOutput(
                hookSpecificOutput: HookSpecificOutput(
                    hookEventName: "PermissionRequest",
                    decision: HookDecision(behavior: "allow", message: nil)
                )
            )
        case .deny:
            output = HookOutput(
                hookSpecificOutput: HookSpecificOutput(
                    hookEventName: "PermissionRequest",
                    decision: HookDecision(
                        behavior: "deny",
                        message: "User denied via asuku notification"
                    )
                )
            )
        }

        let encoder = JSONEncoder()
        let outputData = try encoder.encode(output)

        // Write to stdout
        FileHandle.standardOutput.write(outputData)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

enum PermissionRequestError: Error, CustomStringConvertible {
    case requestIdMismatch(expected: String, got: String)

    var description: String {
        switch self {
        case .requestIdMismatch(let expected, let got):
            return "Request ID mismatch: expected \(expected), got \(got)"
        }
    }
}

import Foundation
import InlineSnapshotTesting
import Testing

@testable import AsukuShared

@Suite("IPCProtocol Tests")
struct IPCProtocolTests {

    // MARK: - Wire Format

    @Test("Wire format encode/decode roundtrip")
    func wireFormatRoundtrip() throws {
        let original = Data("hello world".utf8)
        let encoded = IPCWireFormat.encode(original)

        // Should have 4 byte length prefix + payload
        #expect(encoded.count == 4 + original.count)

        let decoded = IPCWireFormat.decode(encoded)
        #expect(decoded != nil)
        #expect(decoded?.payload == original)
        #expect(decoded?.bytesConsumed == encoded.count)
    }

    @Test("Wire format decode with insufficient data returns nil")
    func wireFormatInsufficientData() {
        // Less than 4 bytes
        let tooShort = Data([0x00, 0x01])
        #expect(IPCWireFormat.decode(tooShort) == nil)

        // Length says 10 bytes but only 2 available
        var lengthPrefix = UInt32(10).bigEndian
        var data = Data(bytes: &lengthPrefix, count: 4)
        data.append(Data([0x01, 0x02]))
        #expect(IPCWireFormat.decode(data) == nil)
    }

    @Test("Wire format empty payload")
    func wireFormatEmptyPayload() {
        let empty = Data()
        let encoded = IPCWireFormat.encode(empty)
        let decoded = IPCWireFormat.decode(encoded)
        #expect(decoded != nil)
        #expect(decoded?.payload.count == 0)
    }

    // MARK: - IPCMessage

    @Test("IPCMessage with PermissionRequest encodes and decodes")
    func permissionRequestRoundtrip() throws {
        let event = PermissionRequestEvent(
            requestId: "test-uuid-123",
            sessionId: "session-1",
            toolName: "Bash",
            toolInput: [
                "command": .string("ls -la")
            ],
            cwd: "/tmp/test"
        )
        let message = IPCMessage(payload: .permissionRequest(event))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(message)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(IPCMessage.self, from: data)

        #expect(decoded.protocolVersion == ipcProtocolVersion)
        if case .permissionRequest(let decodedEvent) = decoded.payload {
            #expect(decodedEvent.requestId == "test-uuid-123")
            #expect(decodedEvent.sessionId == "session-1")
            #expect(decodedEvent.toolName == "Bash")
            #expect(decodedEvent.cwd == "/tmp/test")
            #expect(decodedEvent.toolInput["command"]?.stringValue == "ls -la")
        } else {
            Issue.record("Expected permissionRequest payload")
        }
    }

    @Test("IPCMessage with Notification encodes and decodes")
    func notificationRoundtrip() throws {
        let event = NotificationEvent(
            sessionId: "session-2",
            title: "Test Title",
            body: "Test Body"
        )
        let message = IPCMessage(payload: .notification(event))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(message)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(IPCMessage.self, from: data)

        if case .notification(let decodedEvent) = decoded.payload {
            #expect(decodedEvent.sessionId == "session-2")
            #expect(decodedEvent.title == "Test Title")
            #expect(decodedEvent.body == "Test Body")
        } else {
            Issue.record("Expected notification payload")
        }
    }

    @Test("IPCMessage with Heartbeat encodes and decodes")
    func heartbeatRoundtrip() throws {
        let message = IPCMessage(payload: .heartbeat)

        let encoder = JSONEncoder()
        let data = try encoder.encode(message)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(IPCMessage.self, from: data)

        if case .heartbeat = decoded.payload {
            // Success
        } else {
            Issue.record("Expected heartbeat payload")
        }
    }

    // MARK: - IPCResponse

    @Test("IPCResponse roundtrip")
    func responseRoundtrip() throws {
        let response = IPCResponse(
            requestId: "req-123",
            decision: .allow
        )

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(IPCResponse.self, from: data)

        #expect(decoded.protocolVersion == ipcProtocolVersion)
        #expect(decoded.requestId == "req-123")
        #expect(decoded.decision == .allow)
    }

    @Test("IPCResponse deny decision")
    func responseDeny() throws {
        let response = IPCResponse(
            requestId: "req-456",
            decision: .deny
        )

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(IPCResponse.self, from: data)

        #expect(decoded.decision == .deny)
    }

    // MARK: - AnyCodableValue

    @Test("AnyCodableValue handles all types")
    func anyCodableAllTypes() throws {
        let dict: [String: AnyCodableValue] = [
            "string": .string("hello"),
            "int": .int(42),
            "double": .double(3.14),
            "bool": .bool(true),
            "null": .null,
            "array": .array([.string("a"), .int(1)]),
            "nested": .dictionary(["key": .string("value")]),
        ]

        let data = try JSONEncoder().encode(dict)
        let decoded = try JSONDecoder().decode([String: AnyCodableValue].self, from: data)

        #expect(decoded["string"]?.stringValue == "hello")
        if case .int(let i) = decoded["int"] { #expect(i == 42) }
        if case .bool(let b) = decoded["bool"] { #expect(b == true) }
        if case .null = decoded["null"] {} else { Issue.record("Expected null") }
    }

    @Test("AnyCodableValue description for all types")
    func anyCodableDescription() {
        #expect(AnyCodableValue.string("hello").description == "hello")
        #expect(AnyCodableValue.int(42).description == "42")
        #expect(AnyCodableValue.double(3.14).description == "3.14")
        #expect(AnyCodableValue.bool(true).description == "true")
        #expect(AnyCodableValue.bool(false).description == "false")
        #expect(AnyCodableValue.null.description == "null")
    }

    @Test("AnyCodableValue stringValue returns nil for non-string")
    func anyCodableStringValueNil() {
        #expect(AnyCodableValue.int(42).stringValue == nil)
        #expect(AnyCodableValue.bool(true).stringValue == nil)
        #expect(AnyCodableValue.null.stringValue == nil)
    }

    @Test("AnyCodableValue dictionaryValue returns nil for non-dictionary")
    func anyCodableDictionaryValueNil() {
        #expect(AnyCodableValue.string("hello").dictionaryValue == nil)
        #expect(AnyCodableValue.int(42).dictionaryValue == nil)
        #expect(AnyCodableValue.null.dictionaryValue == nil)
    }

    @Test("AnyCodableValue dictionaryValue returns dict for dictionary")
    func anyCodableDictionaryValue() {
        let value = AnyCodableValue.dictionary(["key": .string("val")])
        let dict = value.dictionaryValue
        #expect(dict != nil)
        #expect(dict?["key"]?.stringValue == "val")
    }

    @Test("AnyCodableValue array description")
    func anyCodableArrayDescription() {
        let arr = AnyCodableValue.array([.string("a"), .int(1)])
        #expect(arr.description.contains("a"))
        #expect(arr.description.contains("1"))
    }

    // MARK: - Protocol Version

    @Test("Protocol version is 1")
    func protocolVersion() {
        #expect(ipcProtocolVersion == 1)
    }

    @Test("IPCMessage defaults to current protocol version")
    func messageDefaultVersion() {
        let message = IPCMessage(payload: .heartbeat)
        #expect(message.protocolVersion == ipcProtocolVersion)
    }

    // MARK: - Request ID Uniqueness

    @Test("UUID request IDs are unique")
    func requestIdUniqueness() {
        let ids = (0..<100).map { _ in UUID().uuidString }
        let uniqueIds = Set(ids)
        #expect(ids.count == uniqueIds.count)
    }

    // MARK: - Sanitization

    @Test("Sanitizer masks sensitive patterns")
    func sanitizeSensitivePatterns() {
        let input = "curl -H \"Authorization: Bearer sk-1234567890\""
        let sanitized = InputSanitizer.sanitize(input)
        #expect(!sanitized.contains("sk-1234567890"))
        #expect(sanitized.contains("***"))
    }

    @Test("Sanitizer masks TOKEN= pattern")
    func sanitizeTokenPattern() {
        let input = "TOKEN=mysecrettoken123 npm run build"
        let sanitized = InputSanitizer.sanitize(input)
        #expect(!sanitized.contains("mysecrettoken123"))
        #expect(sanitized.contains("TOKEN=***"))
    }

    @Test("Sanitizer masks API_KEY= pattern")
    func sanitizeApiKeyPattern() {
        let input = "API_KEY=abc123 python script.py"
        let sanitized = InputSanitizer.sanitize(input)
        #expect(!sanitized.contains("abc123"))
        #expect(sanitized.contains("API_KEY=***"))
    }

    @Test("Sanitizer truncates long strings")
    func sanitizeTruncation() {
        let longInput = String(repeating: "a", count: 500)
        let sanitized = InputSanitizer.sanitizeForNotification(longInput, maxLength: 200)
        #expect(sanitized.count <= 203)  // 200 + "..."
        #expect(sanitized.hasSuffix("..."))
    }

    @Test("Sanitizer preserves non-sensitive content")
    func sanitizePreservesNormal() {
        let input = "ls -la /tmp/project"
        let sanitized = InputSanitizer.sanitize(input)
        #expect(sanitized == input)
    }

    @Test("Sanitizer masks SECRET= pattern")
    func sanitizeSecretPattern() {
        let input = "SECRET=hidden_value script.sh"
        let sanitized = InputSanitizer.sanitize(input)
        #expect(!sanitized.contains("hidden_value"))
        #expect(sanitized.contains("SECRET=***"))
    }

    @Test("Sanitizer masks PASSWORD= pattern")
    func sanitizePasswordPattern() {
        let input = "PASSWORD=my_pass123 login"
        let sanitized = InputSanitizer.sanitize(input)
        #expect(!sanitized.contains("my_pass123"))
        #expect(sanitized.contains("PASSWORD=***"))
    }

    @Test("Sanitizer masks PRIVATE_KEY= pattern")
    func sanitizePrivateKeyPattern() {
        let input = "PRIVATE_KEY=pk_live_abcdef setup"
        let sanitized = InputSanitizer.sanitize(input)
        #expect(!sanitized.contains("pk_live_abcdef"))
        #expect(sanitized.contains("PRIVATE_KEY=***"))
    }

    @Test("Sanitizer masks AWS_SECRET pattern")
    func sanitizeAwsSecretPattern() {
        let input = "AWS_SECRET=wJalrXUtnFEMI deploy"
        let sanitized = InputSanitizer.sanitize(input)
        #expect(!sanitized.contains("wJalrXUtnFEMI"))
    }

    @Test("Sanitizer masks GITHUB_TOKEN pattern")
    func sanitizeGithubTokenPattern() {
        let input = "GITHUB_TOKEN=ghp_xxxxxxxxxxxx push"
        let sanitized = InputSanitizer.sanitize(input)
        #expect(!sanitized.contains("ghp_xxxxxxxxxxxx"))
    }

    @Test("Sanitizer masks NPM_TOKEN pattern")
    func sanitizeNpmTokenPattern() {
        let input = "NPM_TOKEN=npm_xxxxxxxxxxxx publish"
        let sanitized = InputSanitizer.sanitize(input)
        #expect(!sanitized.contains("npm_xxxxxxxxxxxx"))
    }

    @Test("Sanitizer masks Basic auth pattern")
    func sanitizeBasicAuthPattern() {
        let input = "Authorization: Basic dXNlcjpwYXNz"
        let sanitized = InputSanitizer.sanitize(input)
        #expect(sanitized.contains("***"))
    }

    @Test("Sanitizer case insensitive matching")
    func sanitizeCaseInsensitive() {
        let input = "token=secret_value run"
        let sanitized = InputSanitizer.sanitize(input)
        #expect(!sanitized.contains("secret_value"))
    }

    @Test("sanitizeForNotification with short string returns unchanged")
    func sanitizeForNotificationShort() {
        let input = "hello world"
        let sanitized = InputSanitizer.sanitizeForNotification(input)
        #expect(sanitized == input)
    }

    @Test("sanitizeForNotification custom maxLength")
    func sanitizeForNotificationCustomLength() {
        let input = String(repeating: "x", count: 100)
        let sanitized = InputSanitizer.sanitizeForNotification(input, maxLength: 50)
        #expect(sanitized.count <= 53)
        #expect(sanitized.hasSuffix("..."))
    }

    @Test("Sanitizer stops at delimiter characters")
    func sanitizeStopsAtDelimiters() {
        // Value stops at whitespace
        let input1 = "TOKEN=secret123 rest"
        let sanitized1 = InputSanitizer.sanitize(input1)
        #expect(sanitized1.contains("TOKEN=***"))
        #expect(sanitized1.contains("rest"))

        // Value stops at quote
        let input2 = "TOKEN=secret123\" other"
        let sanitized2 = InputSanitizer.sanitize(input2)
        #expect(sanitized2.contains("***"))

        // Value stops at comma
        let input3 = "TOKEN=secret123,other"
        let sanitized3 = InputSanitizer.sanitize(input3)
        #expect(sanitized3.contains("***"))
    }

    // MARK: - Snapshot: JSON format of IPC messages

    @Test("snapshot PermissionRequest JSON format")
    func snapshotPermissionRequestJSON() throws {
        let event = PermissionRequestEvent(
            requestId: "req-001",
            sessionId: "sess-001",
            toolName: "Bash",
            toolInput: ["command": .string("echo hello")],
            cwd: "/home/user",
            timestamp: Date(timeIntervalSince1970: 1700000000)
        )
        let message = IPCMessage(payload: .permissionRequest(event))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        assertInlineSnapshot(of: message, as: .json(encoder)) {
            """
            {
              "payload" : {
                "data" : {
                  "cwd" : "\\/home\\/user",
                  "requestId" : "req-001",
                  "sessionId" : "sess-001",
                  "timestamp" : "2023-11-14T22:13:20Z",
                  "toolInput" : {
                    "command" : "echo hello"
                  },
                  "toolName" : "Bash"
                },
                "type" : "permissionRequest"
              },
              "protocolVersion" : 1
            }
            """
        }
    }

    @Test("snapshot Notification JSON format")
    func snapshotNotificationJSON() throws {
        let event = NotificationEvent(
            sessionId: "sess-002",
            title: "Task Complete",
            body: "Build succeeded",
            timestamp: Date(timeIntervalSince1970: 1700000000)
        )
        let message = IPCMessage(payload: .notification(event))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        assertInlineSnapshot(of: message, as: .json(encoder)) {
            """
            {
              "payload" : {
                "data" : {
                  "body" : "Build succeeded",
                  "sessionId" : "sess-002",
                  "timestamp" : "2023-11-14T22:13:20Z",
                  "title" : "Task Complete"
                },
                "type" : "notification"
              },
              "protocolVersion" : 1
            }
            """
        }
    }

    @Test("snapshot Heartbeat JSON format")
    func snapshotHeartbeatJSON() throws {
        let message = IPCMessage(payload: .heartbeat)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        assertInlineSnapshot(of: message, as: .json(encoder)) {
            """
            {
              "payload" : {
                "type" : "heartbeat"
              },
              "protocolVersion" : 1
            }
            """
        }
    }

    @Test("snapshot IPCResponse JSON format")
    func snapshotResponseJSON() throws {
        let response = IPCResponse(requestId: "req-001", decision: .allow)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        assertInlineSnapshot(of: response, as: .json(encoder)) {
            """
            {
              "decision" : "allow",
              "protocolVersion" : 1,
              "requestId" : "req-001"
            }
            """
        }
    }

    @Test("snapshot IPCError JSON format")
    func snapshotErrorJSON() throws {
        let error = IPCError(error: "Protocol version mismatch")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        assertInlineSnapshot(of: error, as: .json(encoder)) {
            """
            {
              "error" : "Protocol version mismatch",
              "protocolVersion" : 1
            }
            """
        }
    }

    // MARK: - StatusUpdate payload

    @Test("IPCMessage with StatusUpdate encodes and decodes")
    func statusUpdateRoundtrip() throws {
        let statusline = StatuslineData(
            sessionId: "sess-su",
            model: ModelInfo(id: "claude-opus-4-6", displayName: "Opus 4.6"),
            contextWindow: ContextWindowInfo(usedPercentage: 78)
        )
        let event = StatusUpdateEvent(
            sessionId: "sess-su",
            statusline: statusline,
            timestamp: Date(timeIntervalSince1970: 1700000000)
        )
        let message = IPCMessage(payload: .statusUpdate(event))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(message)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(IPCMessage.self, from: data)

        if case .statusUpdate(let decodedEvent) = decoded.payload {
            #expect(decodedEvent.sessionId == "sess-su")
            #expect(decodedEvent.statusline.model?.displayName == "Opus 4.6")
            #expect(decodedEvent.statusline.contextWindow?.usedPercentage == 78)
        } else {
            Issue.record("Expected statusUpdate payload")
        }
    }

    // MARK: - Unknown payload

    @Test("Unknown payload type decodes gracefully")
    func unknownPayloadDecode() throws {
        let json = """
            {
                "protocolVersion": 1,
                "payload": {"type": "future_feature", "data": {"key": "value"}}
            }
            """
        let decoded = try JSONDecoder().decode(IPCMessage.self, from: Data(json.utf8))
        if case .unknown(let typeString) = decoded.payload {
            #expect(typeString == "future_feature")
        } else {
            Issue.record("Expected unknown payload")
        }
    }

    @Test("Unknown payload encodes type string correctly")
    func unknownPayloadEncode() throws {
        let message = IPCMessage(payload: .unknown("experimental"))
        let data = try JSONEncoder().encode(message)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let payload = json["payload"] as! [String: Any]
        #expect(payload["type"] as? String == "experimental")
        // unknown payload should not have data key
        #expect(payload["data"] == nil)
    }

    @Test("Unknown payload without data key decodes")
    func unknownPayloadNoData() throws {
        let json = """
            {"protocolVersion": 1, "payload": {"type": "mystery"}}
            """
        let decoded = try JSONDecoder().decode(IPCMessage.self, from: Data(json.utf8))
        if case .unknown(let typeString) = decoded.payload {
            #expect(typeString == "mystery")
        } else {
            Issue.record("Expected unknown payload")
        }
    }

    // MARK: - Wire Format Additional

    @Test("Wire format with multiple frames in buffer only decodes first")
    func wireFormatMultipleFrames() {
        let frame1Data = Data("hello".utf8)
        let frame2Data = Data("world".utf8)
        let frame1 = IPCWireFormat.encode(frame1Data)
        let frame2 = IPCWireFormat.encode(frame2Data)

        var buffer = frame1
        buffer.append(frame2)

        let result = IPCWireFormat.decode(buffer)
        #expect(result != nil)
        #expect(result?.payload == frame1Data)
        #expect(result?.bytesConsumed == frame1.count)

        // Remaining bytes should contain frame2
        let remaining = buffer.suffix(from: result!.bytesConsumed)
        let result2 = IPCWireFormat.decode(Data(remaining))
        #expect(result2 != nil)
        #expect(result2?.payload == frame2Data)
    }

    @Test("Wire format exactly at boundary size")
    func wireFormatExactBoundary() {
        let payload = Data(repeating: 0xAB, count: 100)
        let encoded = IPCWireFormat.encode(payload)
        #expect(encoded.count == 104)  // 4 + 100

        let decoded = IPCWireFormat.decode(encoded)
        #expect(decoded?.payload == payload)
        #expect(decoded?.bytesConsumed == 104)
    }

    // MARK: - Sanitizer Additional

    @Test("Sanitizer masks multiple patterns in one string")
    func sanitizeMultiplePatterns() {
        let input = "TOKEN=secret1 API_KEY=secret2 PASSWORD=secret3"
        let sanitized = InputSanitizer.sanitize(input)
        #expect(!sanitized.contains("secret1"))
        #expect(!sanitized.contains("secret2"))
        #expect(!sanitized.contains("secret3"))
        #expect(sanitized.contains("TOKEN=***"))
        #expect(sanitized.contains("API_KEY=***"))
        #expect(sanitized.contains("PASSWORD=***"))
    }

    @Test("sanitizeForNotification with sensitive data and truncation")
    func sanitizeForNotificationCombined() {
        let input = "TOKEN=mysecret " + String(repeating: "a", count: 300)
        let sanitized = InputSanitizer.sanitizeForNotification(input, maxLength: 50)
        #expect(!sanitized.contains("mysecret"))
        #expect(sanitized.count <= 53)
        #expect(sanitized.hasSuffix("..."))
    }

    @Test("Sanitizer with pattern at end of string (no trailing delimiter)")
    func sanitizePatternAtEnd() {
        let input = "TOKEN=endofsecret"
        let sanitized = InputSanitizer.sanitize(input)
        #expect(!sanitized.contains("endofsecret"))
        #expect(sanitized == "TOKEN=***")
    }

    // MARK: - IPCMessage with custom protocol version

    @Test("IPCMessage with explicit protocol version")
    func messageCustomVersion() {
        let message = IPCMessage(protocolVersion: 99, payload: .heartbeat)
        #expect(message.protocolVersion == 99)
    }

    // MARK: - Snapshot: StatusUpdate and Unknown

    @Test("snapshot StatusUpdate JSON format")
    func snapshotStatusUpdateJSON() throws {
        let statusline = StatuslineData(
            sessionId: "sess-snap-su",
            model: ModelInfo(id: "claude-opus-4-6", displayName: "Opus 4.6"),
            contextWindow: ContextWindowInfo(usedPercentage: 78)
        )
        let event = StatusUpdateEvent(
            sessionId: "sess-snap-su",
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
                  "sessionId" : "sess-snap-su",
                  "statusline" : {
                    "context_window" : {
                      "used_percentage" : 78
                    },
                    "model" : {
                      "display_name" : "Opus 4.6",
                      "id" : "claude-opus-4-6"
                    },
                    "session_id" : "sess-snap-su"
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

    @Test("snapshot Unknown payload JSON format")
    func snapshotUnknownJSON() throws {
        let message = IPCMessage(payload: .unknown("future_feature"))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        assertInlineSnapshot(of: message, as: .json(encoder)) {
            """
            {
              "payload" : {
                "type" : "future_feature"
              },
              "protocolVersion" : 1
            }
            """
        }
    }

    // MARK: - SocketPathError

    @Test("SocketPathError.pathTooLong description")
    func socketPathErrorPathTooLong() {
        let longPath = "/very/long/path/that/exceeds/limit"
        let error = SocketPathError.pathTooLong(longPath)
        #expect(error.description.contains("104 character limit"))
        #expect(error.description.contains(longPath))
    }

    @Test("SocketPathError.notADirectory description")
    func socketPathErrorNotADirectory() {
        let error = SocketPathError.notADirectory("/some/file")
        #expect(error.description.contains("Expected directory"))
        #expect(error.description.contains("/some/file"))
    }

    // MARK: - Wire Format: Frame Size Limit

    @Test("Wire format rejects oversized frame length")
    func wireFormatRejectsOversized() {
        var lengthPrefix = (IPCWireFormat.maxFrameSize + 1).bigEndian
        let data = Data(bytes: &lengthPrefix, count: 4) + Data(repeating: 0, count: 10)
        #expect(IPCWireFormat.decode(data) == nil)
    }

    @Test("Wire format rejects extremely large frame length")
    func wireFormatRejectsHugeFrame() {
        var lengthPrefix = UInt32.max.bigEndian
        let data = Data(bytes: &lengthPrefix, count: 4) + Data(repeating: 0, count: 10)
        #expect(IPCWireFormat.decode(data) == nil)
    }

    @Test("Wire format accepts frame at max size")
    func wireFormatAcceptsMaxSize() {
        let payload = Data(repeating: 0x42, count: Int(IPCWireFormat.maxFrameSize))
        let encoded = IPCWireFormat.encode(payload)
        let decoded = IPCWireFormat.decode(encoded)
        #expect(decoded != nil)
        #expect(decoded?.payload.count == Int(IPCWireFormat.maxFrameSize))
    }

    // MARK: - Sanitizer: Multiple Occurrences

    @Test("Sanitizer masks multiple occurrences of same pattern")
    func sanitizeMultipleOccurrences() {
        let input = "TOKEN=first_secret TOKEN=second_secret"
        let sanitized = InputSanitizer.sanitize(input)
        #expect(!sanitized.contains("first_secret"))
        #expect(!sanitized.contains("second_secret"))
        #expect(sanitized == "TOKEN=*** TOKEN=***")
    }

    @Test("Sanitizer masks multiple different patterns in one string")
    func sanitizeMultipleDifferentPatterns() {
        let input = "TOKEN=abc API_KEY=def TOKEN=ghi"
        let sanitized = InputSanitizer.sanitize(input)
        #expect(!sanitized.contains("abc"))
        #expect(!sanitized.contains("def"))
        #expect(!sanitized.contains("ghi"))
        #expect(sanitized == "TOKEN=*** API_KEY=*** TOKEN=***")
    }
}

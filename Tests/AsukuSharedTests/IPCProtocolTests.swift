import Foundation
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
}

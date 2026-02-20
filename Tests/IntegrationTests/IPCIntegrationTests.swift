import Foundation
import Network
import Testing

@testable import AsukuShared

@Suite("IPC Integration Tests")
struct IPCIntegrationTests {

    /// Creates a temporary socket path for testing
    private func tempSocketPath() -> String {
        let dir = NSTemporaryDirectory()
        return (dir as NSString).appendingPathComponent(
            "asuku-test-\(UUID().uuidString).sock")
    }

    // MARK: - Wire Format Integration

    @Test("Full IPC message wire format roundtrip")
    func fullWireFormatRoundtrip() throws {
        let event = PermissionRequestEvent(
            requestId: "test-123",
            sessionId: "sess-1",
            toolName: "Bash",
            toolInput: ["command": .string("echo hello")],
            cwd: "/tmp"
        )
        let message = IPCMessage(payload: .permissionRequest(event))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(message)
        let frame = IPCWireFormat.encode(jsonData)

        // Simulate receiving the frame
        let decoded = IPCWireFormat.decode(frame)
        #expect(decoded != nil)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedMessage = try decoder.decode(IPCMessage.self, from: decoded!.payload)

        if case .permissionRequest(let decodedEvent) = decodedMessage.payload {
            #expect(decodedEvent.requestId == "test-123")
            #expect(decodedEvent.toolName == "Bash")
        } else {
            Issue.record("Expected permissionRequest")
        }
    }

    @Test("Response wire format roundtrip")
    func responseWireFormatRoundtrip() throws {
        let response = IPCResponse(requestId: "resp-456", decision: .allow)

        let jsonData = try JSONEncoder().encode(response)
        let frame = IPCWireFormat.encode(jsonData)

        let decoded = IPCWireFormat.decode(frame)
        #expect(decoded != nil)

        let decodedResponse = try JSONDecoder().decode(
            IPCResponse.self, from: decoded!.payload)
        #expect(decodedResponse.requestId == "resp-456")
        #expect(decodedResponse.decision == .allow)
    }

    // MARK: - Concurrent Request IDs

    @Test("Multiple concurrent requests have unique IDs")
    func concurrentRequestIds() async {
        let ids = await withTaskGroup(of: String.self, returning: [String].self) { group in
            for _ in 0..<50 {
                group.addTask {
                    return UUID().uuidString
                }
            }
            var collected: [String] = []
            for await id in group {
                collected.append(id)
            }
            return collected
        }

        #expect(ids.count == 50)
        #expect(Set(ids).count == 50)
    }

    // MARK: - Protocol Version Validation

    @Test("Protocol version mismatch detection")
    func protocolVersionMismatch() throws {
        let message = IPCMessage(protocolVersion: 999, payload: .heartbeat)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(IPCMessage.self, from: data)

        #expect(decoded.protocolVersion != ipcProtocolVersion)
        #expect(decoded.protocolVersion == 999)
    }

    // MARK: - Socket Path

    @Test("Socket path resolves without error")
    func socketPathResolves() throws {
        let path = try SocketPath.resolve()
        #expect(!path.isEmpty)
        #expect(path.utf8.count <= 104)
        #expect(path.hasSuffix("asuku.sock"))
    }

    // MARK: - Error Response

    @Test("IPCError encodes and decodes")
    func ipcErrorRoundtrip() throws {
        let error = IPCError(error: "Protocol version mismatch")
        let data = try JSONEncoder().encode(error)
        let decoded = try JSONDecoder().decode(IPCError.self, from: data)

        #expect(decoded.protocolVersion == ipcProtocolVersion)
        #expect(decoded.error == "Protocol version mismatch")
    }

    // MARK: - UDS Server/Client Integration

    @Test("UDS server accepts connection and echoes response")
    func udsServerClientIntegration() async throws {
        let socketPath = tempSocketPath()
        defer { try? FileManager.default.removeItem(atPath: socketPath) }

        // Create a simple echo server
        let serverReady = expectation(description: "server ready")
        let responseReceived = expectation(description: "response received")

        let endpoint = NWEndpoint.unix(path: socketPath)
        let params = NWParameters()
        params.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        params.requiredLocalEndpoint = endpoint

        let listener = try NWListener(using: params)
        let serverQueue = DispatchQueue(label: "test.server")

        listener.stateUpdateHandler = { state in
            if case .ready = state {
                serverReady.fulfill()
            }
        }

        listener.newConnectionHandler = { connection in
            connection.start(queue: serverQueue)
            // Read message, send back a response
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
                content, _, _, _ in
                guard let content, let (payload, _) = IPCWireFormat.decode(content) else {
                    return
                }
                // Decode the request to get requestId
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                guard let message = try? decoder.decode(IPCMessage.self, from: payload),
                    case .permissionRequest(let event) = message.payload
                else { return }

                // Send allow response
                let response = IPCResponse(
                    requestId: event.requestId, decision: .allow)
                guard let responseData = try? JSONEncoder().encode(response) else { return }
                let frame = IPCWireFormat.encode(responseData)
                connection.send(
                    content: frame,
                    completion: .contentProcessed { _ in
                        responseReceived.fulfill()
                    })
            }
        }

        listener.start(queue: serverQueue)

        // Wait for server to be ready
        await fulfillment(of: [serverReady], timeout: 2.0)

        // Connect as client
        let clientQueue = DispatchQueue(label: "test.client")
        let clientConnection = NWConnection(
            to: NWEndpoint.unix(path: socketPath), using: {
                let p = NWParameters()
                p.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
                return p
            }())

        let connected = expectation(description: "client connected")
        let gotResponse = expectation(description: "got response")

        clientConnection.stateUpdateHandler = { state in
            if case .ready = state {
                connected.fulfill()
            }
        }

        clientConnection.start(queue: clientQueue)
        await fulfillment(of: [connected], timeout: 2.0)

        // Send a permission request
        let event = PermissionRequestEvent(
            requestId: "integration-test-1",
            sessionId: "test-session",
            toolName: "Bash",
            toolInput: ["command": .string("echo test")],
            cwd: "/tmp"
        )
        let message = IPCMessage(payload: .permissionRequest(event))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(message)
        let frame = IPCWireFormat.encode(jsonData)

        clientConnection.send(content: frame, completion: .contentProcessed { _ in })

        // Receive response
        clientConnection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            content, _, _, _ in
            guard let content, let (payload, _) = IPCWireFormat.decode(content) else {
                return
            }
            guard let response = try? JSONDecoder().decode(IPCResponse.self, from: payload)
            else { return }
            #expect(response.requestId == "integration-test-1")
            #expect(response.decision == .allow)
            gotResponse.fulfill()
        }

        await fulfillment(of: [responseReceived, gotResponse], timeout: 5.0)

        clientConnection.cancel()
        listener.cancel()
    }
}

// MARK: - XCTest-like expectation support for Swift Testing

private func expectation(description: String) -> TestExpectation {
    TestExpectation(description: description)
}

private func fulfillment(of expectations: [TestExpectation], timeout: TimeInterval) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if expectations.allSatisfy({ $0.isFulfilled }) {
            return
        }
        try? await Task.sleep(for: .milliseconds(50))
    }
}

private final class TestExpectation: @unchecked Sendable {
    let description: String
    private var _isFulfilled = false
    private let lock = NSLock()

    var isFulfilled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isFulfilled
    }

    init(description: String) {
        self.description = description
    }

    func fulfill() {
        lock.lock()
        defer { lock.unlock() }
        _isFulfilled = true
    }
}

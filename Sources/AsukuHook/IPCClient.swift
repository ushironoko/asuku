import AsukuShared
import Foundation
import Network

/// Thread-safe mutable state holder for callback-based APIs
private final class ConnectionState: @unchecked Sendable {
    private let lock = NSLock()
    private var _error: Error?
    private var _data = Data()

    var error: Error? {
        get { lock.withLock { _error } }
        set { lock.withLock { _error = newValue } }
    }

    var data: Data {
        get { lock.withLock { _data } }
        set { lock.withLock { _data = newValue } }
    }

    func appendData(_ newData: Data) {
        lock.withLock { _data.append(newData) }
    }
}

/// UDS client for connecting to the asuku app
struct IPCClient: Sendable {
    /// Connection timeout in milliseconds
    static let connectionTimeoutMs: UInt64 = 300
    /// Maximum retry count (total attempts = maxRetries + 1)
    static let maxRetries = 1

    /// Sends a message and waits for a response (blocking)
    static func sendAndReceive(_ message: IPCMessage) throws -> Data {
        let socketPath = try SocketPath.resolve()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(message)
        let frame = IPCWireFormat.encode(jsonData)

        var lastError: Error = IPCClientError.connectionFailed("Unknown error")

        for attempt in 0...maxRetries {
            do {
                return try attemptConnection(
                    socketPath: socketPath, frame: frame, attempt: attempt)
            } catch {
                lastError = error
                if attempt < maxRetries {
                    Thread.sleep(forTimeInterval: 0.05)
                }
            }
        }

        throw lastError
    }

    /// Sends a message without waiting for a response (fire-and-forget)
    static func sendOnly(_ message: IPCMessage) throws {
        let socketPath = try SocketPath.resolve()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(message)
        let frame = IPCWireFormat.encode(jsonData)

        let semaphore = DispatchSemaphore(value: 0)
        let state = ConnectionState()

        let endpoint = NWEndpoint.unix(path: socketPath)
        let params = NWParameters()
        params.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        let connection = NWConnection(to: endpoint, using: params)

        let queue = DispatchQueue(label: "asuku.ipc.client.fireforget")

        connection.stateUpdateHandler = { newState in
            switch newState {
            case .ready:
                connection.send(
                    content: frame,
                    completion: .contentProcessed { sendError in
                        if let sendError {
                            state.error = sendError
                        }
                        semaphore.signal()
                    })
            case .failed(let nwError):
                state.error = IPCClientError.connectionFailed(nwError.localizedDescription)
                semaphore.signal()
            case .waiting(let nwError):
                state.error = IPCClientError.connectionFailed(nwError.localizedDescription)
                connection.cancel()
                semaphore.signal()
            default:
                break
            }
        }

        connection.start(queue: queue)

        let timeout = DispatchTime.now() + .milliseconds(Int(connectionTimeoutMs))
        if semaphore.wait(timeout: timeout) == .timedOut {
            connection.cancel()
            throw IPCClientError.timeout
        }

        connection.cancel()

        if let error = state.error {
            throw error
        }
    }

    private static func attemptConnection(
        socketPath: String, frame: Data, attempt: Int
    ) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        let state = ConnectionState()

        let endpoint = NWEndpoint.unix(path: socketPath)
        let params = NWParameters()
        params.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        let connection = NWConnection(to: endpoint, using: params)

        let queue = DispatchQueue(label: "asuku.ipc.client.\(attempt)")

        connection.stateUpdateHandler = { newState in
            switch newState {
            case .ready:
                connection.send(
                    content: frame,
                    completion: .contentProcessed { sendError in
                        if let sendError {
                            state.error = sendError
                            semaphore.signal()
                            return
                        }
                        receiveLoop(connection: connection, state: state) {
                            semaphore.signal()
                        }
                    })
            case .failed(let nwError):
                state.error = IPCClientError.connectionFailed(nwError.localizedDescription)
                semaphore.signal()
            case .waiting(let nwError):
                state.error = IPCClientError.connectionFailed(nwError.localizedDescription)
                connection.cancel()
                semaphore.signal()
            default:
                break
            }
        }

        connection.start(queue: queue)

        // Wait indefinitely for response (hook timeout handled by Claude Code at 300s)
        semaphore.wait()

        connection.cancel()

        if let error = state.error {
            throw error
        }

        return state.data
    }

    private static func receiveLoop(
        connection: NWConnection,
        state: ConnectionState,
        completion: @escaping @Sendable () -> Void
    ) {
        @Sendable func readMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
                content, _, isComplete, recvError in
                if let recvError {
                    state.error = recvError
                    completion()
                    return
                }
                if let content {
                    state.appendData(content)
                }
                // Try to decode a complete frame
                if let (payload, _) = IPCWireFormat.decode(state.data) {
                    state.data = payload
                    completion()
                    return
                }
                if isComplete {
                    state.error = IPCClientError.connectionClosed
                    completion()
                    return
                }
                readMore()
            }
        }
        readMore()
    }
}

enum IPCClientError: Error, CustomStringConvertible {
    case connectionFailed(String)
    case timeout
    case connectionClosed
    case invalidResponse

    var description: String {
        switch self {
        case .connectionFailed(let reason):
            return "Failed to connect to asuku app: \(reason)"
        case .timeout:
            return "Connection to asuku app timed out"
        case .connectionClosed:
            return "Connection closed before receiving complete response"
        case .invalidResponse:
            return "Invalid response from asuku app"
        }
    }
}

import AsukuAppCore
import AsukuShared
import Foundation
import Network

/// Thread-safe holder for requestId associated with a connection
private final class RequestIdHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var _requestId: String?

    var requestId: String? {
        get { lock.withLock { _requestId } }
        set { lock.withLock { _requestId = newValue } }
    }
}

/// Wraps an NWConnection to allow sending responses back to a connected hook
final class IPCResponder: IPCResponding, Sendable {
    let connection: NWConnection
    private let queue: DispatchQueue

    init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    func send(_ response: IPCResponse) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let jsonData = try encoder.encode(response)
            let frame = IPCWireFormat.encode(jsonData)
            connection.send(
                content: frame,
                completion: .contentProcessed { error in
                    if let error {
                        print("[IPCServer] Failed to send response: \(error)")
                    }
                })
        } catch {
            print("[IPCServer] Failed to encode response: \(error)")
        }
    }

    func sendError(_ message: String) {
        do {
            let encoder = JSONEncoder()
            let errorResponse = IPCError(error: message)
            let jsonData = try encoder.encode(errorResponse)
            let frame = IPCWireFormat.encode(jsonData)
            connection.send(
                content: frame,
                completion: .contentProcessed { _ in })
        } catch {
            print("[IPCServer] Failed to encode error: \(error)")
        }
    }

    func cancel() {
        connection.cancel()
    }
}

/// UDS server that listens for incoming hook connections
final class IPCServer: @unchecked Sendable {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "asuku.ipc.server")
    private let socketPath: String

    /// Called when a permission request event is received
    var onPermissionRequest:
        (@Sendable (PermissionRequestEvent, any IPCResponding) -> Void)?

    /// Called when a notification event is received
    var onNotification: (@Sendable (NotificationEvent) -> Void)?

    /// Called when a status update event is received
    var onStatusUpdate: (@Sendable (StatusUpdateEvent) -> Void)?

    /// Called when a hook disconnects (with the requestId if known)
    var onDisconnect: (@Sendable (String?) -> Void)?

    /// Called when the listener state changes (ready, failed, etc.)
    var onStateChange: (@Sendable (ServerState) -> Void)?

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    func start() throws {
        // Remove stale socket file
        try SocketPath.removeSocketIfExists(socketPath)

        let endpoint = NWEndpoint.unix(path: socketPath)

        let params = NWParameters()
        params.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        params.requiredLocalEndpoint = endpoint

        let listener = try NWListener(using: params)

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("[IPCServer] Listening on \(self?.socketPath ?? "unknown")")
                try? SocketPath.setSocketPermissions(self?.socketPath ?? "")
                self?.onStateChange?(.running)
            case .failed(let error):
                print("[IPCServer] Listener failed: \(error)")
                self?.onStateChange?(.failed(error.localizedDescription))
                self?.listener?.cancel()
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        try? SocketPath.removeSocketIfExists(socketPath)
    }

    private func handleConnection(_ connection: NWConnection) {
        let responder = IPCResponder(connection: connection, queue: queue)
        let requestIdHolder = RequestIdHolder()

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveMessage(
                    connection: connection, responder: responder, requestIdHolder: requestIdHolder)
            case .failed, .cancelled:
                self?.onDisconnect?(requestIdHolder.requestId)
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func receiveMessage(
        connection: NWConnection, responder: IPCResponder, requestIdHolder: RequestIdHolder
    ) {
        final class BufferState: @unchecked Sendable {
            var buffer = Data()
        }
        let state = BufferState()

        @Sendable func readMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
                [weak self] content, _, isComplete, error in
                if let error {
                    print("[IPCServer] Receive error: \(error)")
                    return
                }

                if let content {
                    state.buffer.append(content)
                }

                if let (payload, _) = IPCWireFormat.decode(state.buffer) {
                    self?.processMessage(
                        payload, responder: responder, requestIdHolder: requestIdHolder)
                    return
                }

                if isComplete {
                    return
                }

                readMore()
            }
        }

        readMore()
    }

    private func processMessage(
        _ data: Data, responder: IPCResponder, requestIdHolder: RequestIdHolder
    ) {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let message = try decoder.decode(IPCMessage.self, from: data)

            guard message.protocolVersion == ipcProtocolVersion else {
                responder.sendError(
                    "Protocol version mismatch: expected \(ipcProtocolVersion), got \(message.protocolVersion)"
                )
                responder.cancel()
                return
            }

            switch message.payload {
            case .permissionRequest(let event):
                requestIdHolder.requestId = event.requestId
                onPermissionRequest?(event, responder)
            case .notification(let event):
                onNotification?(event)
                responder.cancel()
            case .heartbeat:
                responder.cancel()
            case .statusUpdate(let event):
                onStatusUpdate?(event)
                responder.cancel()
            case .unknown(let type):
                print("[IPCServer] Unknown payload type: \(type), ignoring")
                responder.cancel()
            }
        } catch {
            print("[IPCServer] Failed to decode message: \(error)")
            responder.sendError("Invalid message format: \(error.localizedDescription)")
            responder.cancel()
        }
    }
}

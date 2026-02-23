import AsukuShared
import Foundation
import Network

/// Lightweight HTTP server for receiving ntfy webhook callbacks.
/// Listens on 127.0.0.1 (localhost only) — cloudflared tunnels traffic from the internet.
final class WebhookServer: @unchecked Sendable {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "asuku.webhook.server")
    private let port: UInt16
    private let secret: String
    private let connectionTimeout: TimeInterval

    /// Called when a webhook response arrives: (requestId, decision)
    var onWebhookResponse: (@Sendable (String, PermissionDecision) -> Void)?

    /// Called when the listener state changes asynchronously
    var onStateChange: (@Sendable (ServerState) -> Void)?

    init(port: UInt16, secret: String, connectionTimeout: TimeInterval = 30) {
        self.port = port
        self.secret = secret
        self.connectionTimeout = connectionTimeout
    }

    func start() throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw WebhookServerError.invalidPort(port)
        }

        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback), port: nwPort
        )

        let listener = try NWListener(using: params)

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("[WebhookServer] Listening on 127.0.0.1:\(self?.port ?? 0)")
                self?.onStateChange?(.running)
            case .failed(let error):
                print("[WebhookServer] Listener failed: \(error)")
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
    }

    // MARK: - Connection handling

    /// Sendable wrapper for DispatchWorkItem (safe: all access is on the same serial queue).
    private final class TimeoutHandle: @unchecked Sendable {
        let workItem: DispatchWorkItem
        init(_ workItem: DispatchWorkItem) { self.workItem = workItem }
        func cancel() { workItem.cancel() }
    }

    private func handleConnection(_ connection: NWConnection) {
        let workItem = DispatchWorkItem { [weak connection] in
            print("[WebhookServer] Connection timed out, closing")
            connection?.cancel()
        }
        queue.asyncAfter(deadline: .now() + connectionTimeout, execute: workItem)
        let timeout = TimeoutHandle(workItem)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveHTTPRequest(connection: connection, timeout: timeout)
            case .failed, .cancelled:
                timeout.cancel()
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func receiveHTTPRequest(connection: NWConnection, timeout: TimeoutHandle) {
        final class BufferState: @unchecked Sendable {
            var buffer = Data()
        }
        let state = BufferState()

        @Sendable func readMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) {
                [weak self] content, _, isComplete, error in
                if let error {
                    print("[WebhookServer] Receive error: \(error)")
                    timeout.cancel()
                    connection.cancel()
                    return
                }

                if let content {
                    state.buffer.append(content)
                }

                // Check if we have a complete HTTP request (headers end with \r\n\r\n)
                if let requestString = String(data: state.buffer, encoding: .utf8),
                    requestString.contains("\r\n\r\n")
                {
                    timeout.cancel()
                    self?.processHTTPRequest(requestString, connection: connection)
                    return
                }

                // Guard against excessively large requests
                if state.buffer.count > 4096 {
                    timeout.cancel()
                    self?.sendHTTPResponse(
                        connection: connection, statusCode: 400, body: "Bad Request")
                    return
                }

                if isComplete {
                    timeout.cancel()
                    self?.sendHTTPResponse(
                        connection: connection, statusCode: 400, body: "Incomplete Request")
                    return
                }

                readMore()
            }
        }

        readMore()
    }

    // MARK: - HTTP request processing

    private func processHTTPRequest(_ raw: String, connection: NWConnection) {
        guard let request = WebhookRequestParser.parse(raw) else {
            sendHTTPResponse(connection: connection, statusCode: 404, body: "Not Found")
            return
        }

        // Validate authentication token (prefer Authorization header, fallback to query param)
        guard WebhookRequestParser.validateToken(request.effectiveToken, expected: secret) else {
            print("[WebhookServer] Rejected request with invalid token for \(request.requestId)")
            sendHTTPResponse(connection: connection, statusCode: 403, body: "Forbidden")
            return
        }

        let decision: PermissionDecision
        switch request.action {
        case "allow":
            decision = .allow
        case "deny":
            decision = .deny
        default:
            sendHTTPResponse(connection: connection, statusCode: 404, body: "Not Found")
            return
        }

        print("[WebhookServer] Received \(decision.rawValue) for \(request.requestId)")

        onWebhookResponse?(request.requestId, decision)
        sendHTTPResponse(connection: connection, statusCode: 200, body: "OK")
    }

    // MARK: - HTTP response

    private func sendHTTPResponse(connection: NWConnection, statusCode: Int, body: String) {
        let statusText: String
        switch statusCode {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 403: statusText = "Forbidden"
        case 404: statusText = "Not Found"
        case 405: statusText = "Method Not Allowed"
        default: statusText = "Error"
        }

        let response = [
            "HTTP/1.1 \(statusCode) \(statusText)",
            "Content-Type: text/plain",
            "Content-Length: \(body.utf8.count)",
            "Connection: close",
            "",
            body,
        ].joined(separator: "\r\n")

        connection.send(
            content: response.data(using: .utf8),
            contentContext: .finalMessage,
            isComplete: true,
            completion: .contentProcessed { _ in
                connection.cancel()
            }
        )
    }
}

// MARK: - Error types

enum WebhookServerError: Error, LocalizedError {
    case invalidPort(UInt16)
    case bindFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPort(let port):
            return "Invalid port number: \(port)"
        case .bindFailed(let reason):
            return "Failed to bind webhook server: \(reason)"
        }
    }
}

import AsukuShared
import Foundation
import Network

/// Lightweight HTTP server for receiving ntfy webhook callbacks.
/// Listens on 127.0.0.1 (localhost only) — cloudflared tunnels traffic from the internet.
final class WebhookServer: @unchecked Sendable {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "asuku.webhook.server")
    private let port: UInt16

    /// Called when a webhook response arrives: (requestId, decision)
    var onWebhookResponse: (@Sendable (String, PermissionDecision) -> Void)?

    init(port: UInt16) {
        self.port = port
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
            case .failed(let error):
                print("[WebhookServer] Listener failed: \(error)")
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

    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveHTTPRequest(connection: connection)
            case .failed, .cancelled:
                break
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func receiveHTTPRequest(connection: NWConnection) {
        final class BufferState: @unchecked Sendable {
            var buffer = Data()
        }
        let state = BufferState()

        @Sendable func readMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) {
                [weak self] content, _, isComplete, error in
                if let error {
                    print("[WebhookServer] Receive error: \(error)")
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
                    self?.processHTTPRequest(requestString, connection: connection)
                    return
                }

                // Guard against excessively large requests
                if state.buffer.count > 4096 {
                    self?.sendHTTPResponse(
                        connection: connection, statusCode: 400, body: "Bad Request")
                    return
                }

                if isComplete {
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
        // Parse request line: "POST /webhook/allow/<id> HTTP/1.1\r\n..."
        guard let requestLine = raw.split(separator: "\r\n", maxSplits: 1).first else {
            sendHTTPResponse(connection: connection, statusCode: 400, body: "Bad Request")
            return
        }

        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else {
            sendHTTPResponse(connection: connection, statusCode: 400, body: "Bad Request")
            return
        }

        let method = String(parts[0])
        let path = String(parts[1])

        guard method == "POST" else {
            sendHTTPResponse(connection: connection, statusCode: 405, body: "Method Not Allowed")
            return
        }

        // Route: POST /webhook/allow/<requestId> or POST /webhook/deny/<requestId>
        let pathComponents = path.split(separator: "/")
        guard pathComponents.count == 3,
            pathComponents[0] == "webhook",
            let action = pathComponents[safe: 1],
            let requestId = pathComponents[safe: 2]
        else {
            sendHTTPResponse(connection: connection, statusCode: 404, body: "Not Found")
            return
        }

        let decision: PermissionDecision
        switch String(action) {
        case "allow":
            decision = .allow
        case "deny":
            decision = .deny
        default:
            sendHTTPResponse(connection: connection, statusCode: 404, body: "Not Found")
            return
        }

        let requestIdString = String(requestId)
        print("[WebhookServer] Received \(decision.rawValue) for \(requestIdString)")

        onWebhookResponse?(requestIdString, decision)
        sendHTTPResponse(connection: connection, statusCode: 200, body: "OK")
    }

    // MARK: - HTTP response

    private func sendHTTPResponse(connection: NWConnection, statusCode: Int, body: String) {
        let statusText: String
        switch statusCode {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
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

// MARK: - Collection safe subscript

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

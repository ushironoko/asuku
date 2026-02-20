import Foundation

/// Parsed webhook callback request
public struct WebhookCallbackRequest: Sendable {
    public let action: String
    public let requestId: String
    public let token: String?

    public init(action: String, requestId: String, token: String?) {
        self.action = action
        self.requestId = requestId
        self.token = token
    }
}

/// Parses and validates incoming webhook HTTP requests.
/// Extracted from WebhookServer to enable unit testing (AsukuApp is an executableTarget).
public enum WebhookRequestParser {
    /// Parses a raw HTTP request string into a WebhookCallbackRequest.
    /// Expected format: `POST /webhook/{allow|deny}/<requestId>?token=<secret> HTTP/1.1`
    public static func parse(_ rawRequest: String) -> WebhookCallbackRequest? {
        guard let requestLine = rawRequest.split(separator: "\r\n", maxSplits: 1).first else {
            return nil
        }

        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else {
            return nil
        }

        let method = String(parts[0])
        guard method == "POST" else {
            return nil
        }

        return parsePath(String(parts[1]))
    }

    /// Parses a webhook path like `/webhook/allow/<id>?token=<secret>`
    public static func parsePath(_ path: String) -> WebhookCallbackRequest? {
        // Split path from query string
        let pathAndQuery = path.split(separator: "?", maxSplits: 1)
        let pathOnly = String(pathAndQuery[0])

        let components = pathOnly.split(separator: "/").map(String.init)
        guard components.count == 3,
            components[0] == "webhook",
            components[1] == "allow" || components[1] == "deny"
        else {
            return nil
        }

        let action = components[1]
        let requestId = components[2]

        // Extract token from query string
        var token: String?
        if pathAndQuery.count > 1 {
            let queryString = String(pathAndQuery[1])
            for param in queryString.split(separator: "&") {
                let kv = param.split(separator: "=", maxSplits: 1)
                if kv.count == 2, kv[0] == "token" {
                    token = String(kv[1])
                }
            }
        }

        return WebhookCallbackRequest(action: action, requestId: requestId, token: token)
    }

    /// Validates a provided token against the expected secret using constant-time comparison.
    public static func validateToken(_ provided: String?, expected: String) -> Bool {
        guard let provided else { return false }
        let providedBytes = Array(provided.utf8)
        let expectedBytes = Array(expected.utf8)
        guard providedBytes.count == expectedBytes.count else { return false }
        var result: UInt8 = 0
        for (a, b) in zip(providedBytes, expectedBytes) {
            result |= a ^ b
        }
        return result == 0
    }
}

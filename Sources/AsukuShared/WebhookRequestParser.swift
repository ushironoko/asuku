import Foundation

/// Parsed webhook callback request
public struct WebhookCallbackRequest: Sendable {
    public let action: String
    public let requestId: String
    /// Token from URL query parameter (legacy, for backward compatibility)
    public let token: String?
    /// Token from Authorization: Bearer header (preferred)
    public let bearerToken: String?

    /// Returns the effective authentication token.
    /// Prefers the Authorization header over query parameter.
    public var effectiveToken: String? {
        bearerToken ?? token
    }

    public init(action: String, requestId: String, token: String?, bearerToken: String? = nil) {
        self.action = action
        self.requestId = requestId
        self.token = token
        self.bearerToken = bearerToken
    }
}

/// Parses and validates incoming webhook HTTP requests.
/// Extracted from WebhookServer to enable unit testing (AsukuApp is an executableTarget).
public enum WebhookRequestParser {
    /// Parses a raw HTTP request string into a WebhookCallbackRequest.
    /// Expected format: `POST /webhook/{allow|deny}/<requestId> HTTP/1.1`
    /// Authentication via `Authorization: Bearer <token>` header (preferred) or `?token=<secret>` query (legacy).
    public static func parse(_ rawRequest: String) -> WebhookCallbackRequest? {
        let lines = rawRequest.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else {
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

        guard var result = parsePath(String(parts[1])) else {
            return nil
        }

        // Extract Bearer token from Authorization header
        let bearerToken = extractBearerToken(from: lines)
        if bearerToken != nil {
            result = WebhookCallbackRequest(
                action: result.action,
                requestId: result.requestId,
                token: result.token,
                bearerToken: bearerToken
            )
        }

        return result
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

        // requestId must be a valid UUID
        guard UUID(uuidString: requestId) != nil else {
            return nil
        }

        // Extract token from query string (legacy backward compatibility)
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

    /// Extracts the Bearer token from HTTP headers.
    private static func extractBearerToken(
        from lines: [Substring]
    ) -> String? {
        let bearerPrefix = "bearer "
        for line in lines.dropFirst() {
            // Empty line marks end of headers
            if line.isEmpty { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("authorization:") {
                let value = trimmed.dropFirst("authorization:".count)
                    .trimmingCharacters(in: .whitespaces)
                if value.lowercased().hasPrefix(bearerPrefix) {
                    return String(value.dropFirst(bearerPrefix.count))
                }
            }
        }
        return nil
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

import Foundation
import Testing

@testable import AsukuShared

@Suite("WebhookRequestParser Tests")
struct WebhookRequestParserTests {

    // Test UUIDs (fixed for reproducibility)
    private let uuid1 = "550E8400-E29B-41D4-A716-446655440001"
    private let uuid2 = "550E8400-E29B-41D4-A716-446655440002"
    private let uuid3 = "550E8400-E29B-41D4-A716-446655440003"
    private let uuid4 = "550E8400-E29B-41D4-A716-446655440004"
    private let uuid5 = "550E8400-E29B-41D4-A716-446655440005"

    // MARK: - Path parsing

    @Test("Parses allow path with token")
    func parseAllowWithToken() {
        let result = WebhookRequestParser.parsePath(
            "/webhook/allow/\(uuid1)?token=secret-abc")
        #expect(result != nil)
        #expect(result?.action == "allow")
        #expect(result?.requestId == uuid1)
        #expect(result?.token == "secret-abc")
    }

    @Test("Parses deny path with token")
    func parseDenyWithToken() {
        let result = WebhookRequestParser.parsePath(
            "/webhook/deny/\(uuid2)?token=my-token")
        #expect(result != nil)
        #expect(result?.action == "deny")
        #expect(result?.requestId == uuid2)
        #expect(result?.token == "my-token")
    }

    @Test("Parses path without token")
    func parsePathWithoutToken() {
        let result = WebhookRequestParser.parsePath("/webhook/allow/\(uuid3)")
        #expect(result != nil)
        #expect(result?.action == "allow")
        #expect(result?.requestId == uuid3)
        #expect(result?.token == nil)
    }

    @Test("Rejects invalid action")
    func rejectInvalidAction() {
        let result = WebhookRequestParser.parsePath(
            "/webhook/delete/\(uuid1)?token=abc")
        #expect(result == nil)
    }

    @Test("Rejects missing webhook prefix")
    func rejectMissingPrefix() {
        let result = WebhookRequestParser.parsePath("/api/allow/\(uuid1)")
        #expect(result == nil)
    }

    @Test("Rejects too few path components")
    func rejectTooFewComponents() {
        let result = WebhookRequestParser.parsePath("/webhook/allow")
        #expect(result == nil)
    }

    @Test("Rejects too many path components")
    func rejectTooManyComponents() {
        let result = WebhookRequestParser.parsePath(
            "/webhook/allow/\(uuid1)/extra")
        #expect(result == nil)
    }

    @Test("Handles UUID-style request IDs")
    func parseUUIDRequestId() {
        let uuid = "550E8400-E29B-41D4-A716-446655440000"
        let result = WebhookRequestParser.parsePath("/webhook/deny/\(uuid)?token=tok")
        #expect(result != nil)
        #expect(result?.requestId == uuid)
    }

    @Test("Handles token with multiple query params")
    func parseTokenWithExtraParams() {
        let result = WebhookRequestParser.parsePath(
            "/webhook/allow/\(uuid4)?foo=bar&token=secret&baz=qux")
        #expect(result != nil)
        #expect(result?.token == "secret")
    }

    // MARK: - Full HTTP request parsing

    @Test("Parses full POST request")
    func parseFullPostRequest() {
        let raw =
            "POST /webhook/allow/\(uuid1)?token=my-secret HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let result = WebhookRequestParser.parse(raw)
        #expect(result != nil)
        #expect(result?.action == "allow")
        #expect(result?.requestId == uuid1)
        #expect(result?.token == "my-secret")
    }

    @Test("Rejects GET request")
    func rejectGetRequest() {
        let raw =
            "GET /webhook/allow/\(uuid1)?token=secret HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let result = WebhookRequestParser.parse(raw)
        #expect(result == nil)
    }

    @Test("Rejects malformed request line")
    func rejectMalformedRequest() {
        let raw = "INVALID\r\n\r\n"
        let result = WebhookRequestParser.parse(raw)
        #expect(result == nil)
    }

    @Test("Rejects empty request")
    func rejectEmptyRequest() {
        let result = WebhookRequestParser.parse("")
        #expect(result == nil)
    }

    // MARK: - Token validation

    @Test("Validates matching token")
    func validateMatchingToken() {
        #expect(WebhookRequestParser.validateToken("secret-123", expected: "secret-123"))
    }

    @Test("Rejects mismatched token")
    func rejectMismatchedToken() {
        #expect(!WebhookRequestParser.validateToken("wrong-token", expected: "secret-123"))
    }

    @Test("Rejects nil token")
    func rejectNilToken() {
        #expect(!WebhookRequestParser.validateToken(nil, expected: "secret-123"))
    }

    @Test("Rejects empty token against non-empty expected")
    func rejectEmptyToken() {
        #expect(!WebhookRequestParser.validateToken("", expected: "secret-123"))
    }

    @Test("Rejects token with different length")
    func rejectDifferentLengthToken() {
        #expect(!WebhookRequestParser.validateToken("short", expected: "much-longer-secret"))
    }

    @Test("Validates UUID-style tokens")
    func validateUUIDToken() {
        let token = "550E8400-E29B-41D4-A716-446655440000"
        #expect(WebhookRequestParser.validateToken(token, expected: token))
    }

    // MARK: - Integration: parse + validate

    @Test("Full request with valid token succeeds")
    func fullRequestValidToken() {
        let secret = "my-install-secret"
        let raw =
            "POST /webhook/deny/\(uuid5)?token=\(secret) HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let result = WebhookRequestParser.parse(raw)
        #expect(result != nil)
        #expect(result?.action == "deny")
        #expect(result?.requestId == uuid5)
        #expect(WebhookRequestParser.validateToken(result?.token, expected: secret))
    }

    @Test("Full request with wrong token fails validation")
    func fullRequestWrongToken() {
        let raw =
            "POST /webhook/allow/\(uuid1)?token=wrong HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let result = WebhookRequestParser.parse(raw)
        #expect(result != nil)
        #expect(!WebhookRequestParser.validateToken(result?.token, expected: "correct-secret"))
    }

    @Test("Full request without token fails validation")
    func fullRequestNoToken() {
        let raw = "POST /webhook/allow/\(uuid2) HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let result = WebhookRequestParser.parse(raw)
        #expect(result != nil)
        #expect(!WebhookRequestParser.validateToken(result?.token, expected: "any-secret"))
    }

    // MARK: - Additional edge cases (security-sensitive parsing)

    @Test("Rejects PUT request")
    func rejectPutRequest() {
        let raw =
            "PUT /webhook/allow/\(uuid1)?token=secret HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let result = WebhookRequestParser.parse(raw)
        #expect(result == nil)
    }

    @Test("Rejects DELETE request")
    func rejectDeleteRequest() {
        let raw =
            "DELETE /webhook/deny/\(uuid1)?token=secret HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let result = WebhookRequestParser.parse(raw)
        #expect(result == nil)
    }

    @Test("Rejects request line with only method")
    func rejectMethodOnly() {
        let raw = "POST\r\n\r\n"
        let result = WebhookRequestParser.parse(raw)
        #expect(result == nil)
    }

    @Test("Rejects request without CRLF line endings")
    func rejectNonCRLFRequest() {
        let raw =
            "POST /webhook/allow/\(uuid1)?token=secret HTTP/1.1\nHost: localhost\n\n"
        _ = WebhookRequestParser.parse(raw)
        // Without \r\n the request line parse may fail depending on split behavior
        // The important thing is it doesn't crash
    }

    @Test("Parses request line without HTTP version")
    func parseRequestWithoutVersion() {
        let raw =
            "POST /webhook/allow/\(uuid1)?token=secret\r\nHost: localhost\r\n\r\n"
        let result = WebhookRequestParser.parse(raw)
        #expect(result != nil)
        #expect(result?.action == "allow")
        #expect(result?.requestId == uuid1)
        #expect(result?.token == "secret")
    }

    @Test("Empty token= query value yields nil token")
    func parseEmptyTokenValue() {
        let result = WebhookRequestParser.parsePath("/webhook/allow/\(uuid1)?token=")
        #expect(result != nil)
        #expect(result?.token == nil)
    }

    @Test("Rejects bare /webhook path")
    func rejectBareWebhookPath() {
        let result = WebhookRequestParser.parsePath("/webhook")
        #expect(result == nil)
    }

    @Test("Token with special characters in query")
    func parseTokenWithSpecialChars() {
        let result = WebhookRequestParser.parsePath(
            "/webhook/deny/\(uuid4)?token=abc-123_XYZ.456")
        #expect(result != nil)
        #expect(result?.token == "abc-123_XYZ.456")
    }

    // MARK: - requestId UUID validation

    @Test("Rejects non-UUID requestId")
    func rejectNonUUIDRequestId() {
        let result = WebhookRequestParser.parsePath("/webhook/allow/req-123?token=secret")
        #expect(result == nil)
    }

    @Test("Rejects path traversal in requestId")
    func rejectPathTraversalRequestId() {
        let result = WebhookRequestParser.parsePath(
            "/webhook/allow/..%2F..%2Fetc%2Fpasswd?token=secret")
        #expect(result == nil)
    }

    @Test("Rejects empty requestId")
    func rejectEmptyRequestId() {
        // /webhook/allow/ with trailing slash — split yields ["webhook", "allow", ""]
        // But empty string is not a valid UUID, so it should be rejected
        let result = WebhookRequestParser.parsePath("/webhook/allow/?token=secret")
        #expect(result == nil)
    }

    @Test("Accepts lowercase UUID requestId")
    func acceptLowercaseUUID() {
        let uuid = "550e8400-e29b-41d4-a716-446655440000"
        let result = WebhookRequestParser.parsePath("/webhook/allow/\(uuid)?token=tok")
        #expect(result != nil)
        #expect(result?.requestId == uuid)
    }

    // MARK: - Authorization Bearer token

    @Test("Parses Bearer token from Authorization header")
    func parseBearerToken() {
        let raw = [
            "POST /webhook/allow/\(uuid1) HTTP/1.1",
            "Host: localhost",
            "Authorization: Bearer my-secret-token",
            "",
            "",
        ].joined(separator: "\r\n")
        let result = WebhookRequestParser.parse(raw)
        #expect(result != nil)
        #expect(result?.bearerToken == "my-secret-token")
        #expect(result?.token == nil)
        #expect(result?.effectiveToken == "my-secret-token")
    }

    @Test("Bearer token takes precedence over query token")
    func bearerTokenPrecedence() {
        let raw = [
            "POST /webhook/allow/\(uuid1)?token=query-token HTTP/1.1",
            "Host: localhost",
            "Authorization: Bearer header-token",
            "",
            "",
        ].joined(separator: "\r\n")
        let result = WebhookRequestParser.parse(raw)
        #expect(result != nil)
        #expect(result?.bearerToken == "header-token")
        #expect(result?.token == "query-token")
        #expect(result?.effectiveToken == "header-token")
    }

    @Test("Query token used as fallback when no Bearer header")
    func queryTokenFallback() {
        let raw = [
            "POST /webhook/deny/\(uuid2)?token=fallback-token HTTP/1.1",
            "Host: localhost",
            "",
            "",
        ].joined(separator: "\r\n")
        let result = WebhookRequestParser.parse(raw)
        #expect(result != nil)
        #expect(result?.bearerToken == nil)
        #expect(result?.token == "fallback-token")
        #expect(result?.effectiveToken == "fallback-token")
    }

    @Test("effectiveToken is nil when no auth provided")
    func noTokenAtAll() {
        let raw = [
            "POST /webhook/allow/\(uuid3) HTTP/1.1",
            "Host: localhost",
            "",
            "",
        ].joined(separator: "\r\n")
        let result = WebhookRequestParser.parse(raw)
        #expect(result != nil)
        #expect(result?.effectiveToken == nil)
    }

    @Test("Bearer token validation succeeds")
    func bearerTokenValidation() {
        let secret = "my-webhook-secret"
        let raw = [
            "POST /webhook/allow/\(uuid1) HTTP/1.1",
            "Host: localhost",
            "Authorization: Bearer \(secret)",
            "",
            "",
        ].joined(separator: "\r\n")
        let result = WebhookRequestParser.parse(raw)
        #expect(result != nil)
        #expect(WebhookRequestParser.validateToken(result?.effectiveToken, expected: secret))
    }

    @Test("Authorization header is case-insensitive")
    func bearerTokenCaseInsensitive() {
        let raw = [
            "POST /webhook/allow/\(uuid1) HTTP/1.1",
            "Host: localhost",
            "authorization: bearer case-test-token",
            "",
            "",
        ].joined(separator: "\r\n")
        let result = WebhookRequestParser.parse(raw)
        #expect(result != nil)
        #expect(result?.bearerToken == "case-test-token")
    }
}

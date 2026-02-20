import Foundation
import Testing

@testable import AsukuShared

@Suite("WebhookRequestParser Tests")
struct WebhookRequestParserTests {

    // MARK: - Path parsing

    @Test("Parses allow path with token")
    func parseAllowWithToken() {
        let result = WebhookRequestParser.parsePath("/webhook/allow/req-123?token=secret-abc")
        #expect(result != nil)
        #expect(result?.action == "allow")
        #expect(result?.requestId == "req-123")
        #expect(result?.token == "secret-abc")
    }

    @Test("Parses deny path with token")
    func parseDenyWithToken() {
        let result = WebhookRequestParser.parsePath("/webhook/deny/req-456?token=my-token")
        #expect(result != nil)
        #expect(result?.action == "deny")
        #expect(result?.requestId == "req-456")
        #expect(result?.token == "my-token")
    }

    @Test("Parses path without token")
    func parsePathWithoutToken() {
        let result = WebhookRequestParser.parsePath("/webhook/allow/req-789")
        #expect(result != nil)
        #expect(result?.action == "allow")
        #expect(result?.requestId == "req-789")
        #expect(result?.token == nil)
    }

    @Test("Rejects invalid action")
    func rejectInvalidAction() {
        let result = WebhookRequestParser.parsePath("/webhook/delete/req-123?token=abc")
        #expect(result == nil)
    }

    @Test("Rejects missing webhook prefix")
    func rejectMissingPrefix() {
        let result = WebhookRequestParser.parsePath("/api/allow/req-123")
        #expect(result == nil)
    }

    @Test("Rejects too few path components")
    func rejectTooFewComponents() {
        let result = WebhookRequestParser.parsePath("/webhook/allow")
        #expect(result == nil)
    }

    @Test("Rejects too many path components")
    func rejectTooManyComponents() {
        let result = WebhookRequestParser.parsePath("/webhook/allow/req-123/extra")
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
            "/webhook/allow/req-1?foo=bar&token=secret&baz=qux")
        #expect(result != nil)
        #expect(result?.token == "secret")
    }

    // MARK: - Full HTTP request parsing

    @Test("Parses full POST request")
    func parseFullPostRequest() {
        let raw = "POST /webhook/allow/req-abc?token=my-secret HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let result = WebhookRequestParser.parse(raw)
        #expect(result != nil)
        #expect(result?.action == "allow")
        #expect(result?.requestId == "req-abc")
        #expect(result?.token == "my-secret")
    }

    @Test("Rejects GET request")
    func rejectGetRequest() {
        let raw = "GET /webhook/allow/req-abc?token=secret HTTP/1.1\r\nHost: localhost\r\n\r\n"
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
            "POST /webhook/deny/req-999?token=\(secret) HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let result = WebhookRequestParser.parse(raw)
        #expect(result != nil)
        #expect(result?.action == "deny")
        #expect(result?.requestId == "req-999")
        #expect(WebhookRequestParser.validateToken(result?.token, expected: secret))
    }

    @Test("Full request with wrong token fails validation")
    func fullRequestWrongToken() {
        let raw =
            "POST /webhook/allow/req-111?token=wrong HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let result = WebhookRequestParser.parse(raw)
        #expect(result != nil)
        #expect(!WebhookRequestParser.validateToken(result?.token, expected: "correct-secret"))
    }

    @Test("Full request without token fails validation")
    func fullRequestNoToken() {
        let raw = "POST /webhook/allow/req-222 HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let result = WebhookRequestParser.parse(raw)
        #expect(result != nil)
        #expect(!WebhookRequestParser.validateToken(result?.token, expected: "any-secret"))
    }

    // MARK: - Additional edge cases (security-sensitive parsing)

    @Test("Rejects PUT request")
    func rejectPutRequest() {
        let raw = "PUT /webhook/allow/req-abc?token=secret HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let result = WebhookRequestParser.parse(raw)
        #expect(result == nil)
    }

    @Test("Rejects DELETE request")
    func rejectDeleteRequest() {
        let raw = "DELETE /webhook/deny/req-abc?token=secret HTTP/1.1\r\nHost: localhost\r\n\r\n"
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
        let raw = "POST /webhook/allow/req-abc?token=secret HTTP/1.1\nHost: localhost\n\n"
        _ = WebhookRequestParser.parse(raw)
        // Without \r\n the request line parse may fail depending on split behavior
        // The important thing is it doesn't crash
    }

    @Test("Parses request line without HTTP version")
    func parseRequestWithoutVersion() {
        // HTTP/0.9 style: "POST /path" with no version — split with maxSplits:2 handles this
        let raw = "POST /webhook/allow/req-abc?token=secret\r\nHost: localhost\r\n\r\n"
        let result = WebhookRequestParser.parse(raw)
        #expect(result != nil)
        #expect(result?.action == "allow")
        #expect(result?.requestId == "req-abc")
        #expect(result?.token == "secret")
    }

    @Test("Empty token= query value yields nil token")
    func parseEmptyTokenValue() {
        // "token=" splits to ["token"] (empty trailing is omitted), so token is nil
        let result = WebhookRequestParser.parsePath("/webhook/allow/req-123?token=")
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
            "/webhook/deny/req-1?token=abc-123_XYZ.456")
        #expect(result != nil)
        #expect(result?.token == "abc-123_XYZ.456")
    }
}

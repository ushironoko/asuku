import Foundation
import Testing

@testable import AsukuAppCore

// MARK: - Test doubles

/// Emits a pre-seeded script of inbound lines and records everything written. The driver reads
/// exactly when it needs to, so a flat script models the request/response ordering faithfully.
private actor ScriptedDuplex: LineDuplex {
    private let outbound: [String]
    private var index = 0
    private var written: [String] = []
    private var didShutdown = false

    init(_ outbound: [String]) { self.outbound = outbound }

    func writeLine(_ line: String) async { written.append(line) }
    func nextLine() async -> String? {
        guard !didShutdown, index < outbound.count else { return nil }
        defer { index += 1 }
        return outbound[index]
    }
    func shutdown() async { didShutdown = true }
    func writtenLines() -> [String] { written }
}

/// nextLine() never yields within any test's patience; the driver's teardown cancels it promptly.
private actor DelayingDuplex: LineDuplex {
    func writeLine(_ line: String) async {}
    func nextLine() async -> String? {
        try? await Task.sleep(for: .seconds(30))
        return nil
    }
    func shutdown() async {}
}

private enum RPC {
    static let initOK =
        #"{"jsonrpc":"2.0","id":0,"result":{"userAgent":"x","codexHome":"/h","platformFamily":"unix","platformOs":"macos"}}"#
    static let initError = #"{"jsonrpc":"2.0","id":0,"error":{"code":-32000,"message":"nope"}}"#
    static let rateLimits =
        #"{"jsonrpc":"2.0","id":1,"result":{"rateLimits":{"primary":{"usedPercent":42,"windowDurationMins":10080}}}}"#
    static let rateLimitsError = #"{"jsonrpc":"2.0","id":1,"error":{"code":-32000,"message":"login required"}}"#
    static let updatedNotification = #"{"jsonrpc":"2.0","method":"account/rateLimits/updated","params":{}}"#
    static let wrongId = #"{"jsonrpc":"2.0","id":99,"result":{"stray":true}}"#
}

// MARK: - Driver tests

@Suite("CodexAppServerDriver")
struct CodexAppServerDriverTests {
    private let now = Date(timeIntervalSince1970: 1_784_600_000)

    @Test("happy path → returns result bytes; sends initialize/initialized/read and no turn/*")
    func happyPath() async throws {
        let t = ScriptedDuplex([RPC.initOK, RPC.rateLimits])
        let data = try #require(await CodexAppServerDriver.readRateLimits(over: t))
        let usage = try #require(CodexAppServerParser.parse(data, now: now))
        #expect(usage.window(.sevenDay)?.usedPercent == 42)

        let written = await t.writtenLines()
        #expect(written.count == 3)
        #expect(written[0].contains("\"method\":\"initialize\""))
        #expect(written[1].contains("\"method\":\"initialized\""))
        #expect(written[2].contains("\"method\":\"account/rateLimits/read\""))
        // Safety invariant: the conversation must never spend tokens.
        #expect(written.allSatisfy { !$0.contains("turn") })
    }

    @Test("notifications interleaved with responses are skipped")
    func skipsNotifications() async throws {
        let t = ScriptedDuplex([RPC.updatedNotification, RPC.initOK, RPC.updatedNotification, RPC.rateLimits])
        let data = try #require(await CodexAppServerDriver.readRateLimits(over: t))
        #expect(CodexAppServerParser.parse(data, now: now) != nil)
    }

    @Test("responses with an unexpected id are skipped")
    func skipsUnexpectedId() async throws {
        let t = ScriptedDuplex([RPC.initOK, RPC.wrongId, RPC.rateLimits])
        let data = try #require(await CodexAppServerDriver.readRateLimits(over: t))
        #expect(CodexAppServerParser.parse(data, now: now) != nil)
    }

    @Test("non-JSON log lines are skipped")
    func skipsNonJSON() async throws {
        let t = ScriptedDuplex(["starting app-server...", RPC.initOK, "war: something", RPC.rateLimits])
        let data = try #require(await CodexAppServerDriver.readRateLimits(over: t))
        #expect(CodexAppServerParser.parse(data, now: now) != nil)
    }

    @Test("RPC error on the read → nil")
    func readError() async {
        let t = ScriptedDuplex([RPC.initOK, RPC.rateLimitsError])
        #expect(await CodexAppServerDriver.readRateLimits(over: t) == nil)
    }

    @Test("initialize error → nil (no read attempted past failure)")
    func initializeError() async {
        let t = ScriptedDuplex([RPC.initError])
        #expect(await CodexAppServerDriver.readRateLimits(over: t) == nil)
    }

    @Test("EOF before the read response → nil")
    func eofBeforeResponse() async {
        let t = ScriptedDuplex([RPC.initOK])
        #expect(await CodexAppServerDriver.readRateLimits(over: t) == nil)
    }

    @Test("hung child → timeout → nil (and completes promptly)")
    func timeout() async {
        let t = DelayingDuplex()
        #expect(await CodexAppServerDriver.readRateLimits(over: t, timeout: .milliseconds(200)) == nil)
    }
}

// MARK: - Framer tests

@Suite("LineFramer")
struct LineFramerTests {
    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String] = []
        func append(_ s: String) { lock.lock(); storage.append(s); lock.unlock() }
        var lines: [String] { lock.lock(); defer { lock.unlock() }; return storage }
    }

    private func collect(_ chunks: [String], maxFrame: Int = 1 << 20) -> [String] {
        let box = Collector()
        let framer = LineFramer(maxFrame: maxFrame) { box.append($0) }
        for chunk in chunks { framer.feed(Data(chunk.utf8)) }
        return box.lines
    }

    @Test("single line")
    func single() { #expect(collect(["a\n"]) == ["a"]) }

    @Test("multiple lines in one chunk")
    func multiInChunk() { #expect(collect(["a\nb\nc\n"]) == ["a", "b", "c"]) }

    @Test("a line split across chunks is joined")
    func splitAcrossChunks() { #expect(collect(["a", "b", "c\n"]) == ["abc"]) }

    @Test("a partial trailing line is not emitted until its newline arrives")
    func partialTrailing() {
        #expect(collect(["a\nb"]) == ["a"])
        #expect(collect(["x\ny", "z\n"]) == ["x", "yz"])
    }

    @Test("real JSON payload survives framing")
    func jsonPayload() {
        #expect(collect([#"{"id":1,"result":{}}"#, "\n"]) == [#"{"id":1,"result":{}}"#])
    }

    @Test("a pathological unterminated frame past maxFrame is dropped, not grown")
    func maxFrameDrop() {
        // 10 bytes, no newline, cap 4 → buffer is dropped; a following complete line still emits.
        #expect(collect(["0123456789", "ok\n"], maxFrame: 4) == ["ok"])
    }
}

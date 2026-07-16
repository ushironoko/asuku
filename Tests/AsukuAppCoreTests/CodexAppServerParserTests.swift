import Foundation
import Testing

@testable import AsukuAppCore

@Suite("CodexAppServerParser")
struct CodexAppServerParserTests {
    private let now = Date(timeIntervalSince1970: 1_784_600_000)

    @Test("full snapshot → 5h + weekly windows, credits, planType, reset credits")
    func full() throws {
        let usage = try #require(
            CodexAppServerParser.parse(try Fixture.data("codex-appserver-full.json"), now: now)
        )
        #expect(usage.provider == .codex)
        #expect(usage.source == .codexAppServer)
        #expect(usage.observedAt == now)
        #expect(usage.window(.fiveHour)?.usedPercent == 12)
        #expect(usage.window(.sevenDay)?.usedPercent == 42)
        #expect(usage.window(.sevenDay)?.resetsAt == Date(timeIntervalSince1970: 1_784_695_154))
        #expect(usage.credits?.hasCredits == true)
        #expect(usage.credits?.balance == 5.5)
        #expect(usage.planType == "pro")
        #expect(usage.resetCreditsAvailable == 4)
    }

    @Test("secondary null → primary-only window (real probe shape)")
    func secondaryNull() throws {
        let usage = try #require(
            CodexAppServerParser.parse(try Fixture.data("codex-appserver-secondary-null.json"), now: now)
        )
        #expect(usage.windows.count == 1)
        // primary has windowDurationMins 10080 → weekly (mapping keys off duration, not slot)
        #expect(usage.window(.sevenDay)?.usedPercent == 42)
        #expect(usage.window(.fiveHour) == nil)
        #expect(usage.credits?.balance == 0) // "0" → 0.0
        #expect(usage.resetCreditsAvailable == 4)
    }

    @Test("non-numeric balance → nil balance, no crash")
    func nonNumericBalance() {
        let json = #"{"rateLimits":{"primary":{"usedPercent":5,"windowDurationMins":300},"credits":{"hasCredits":true,"balance":"abc"}}}"#
        let usage = CodexAppServerParser.parse(Data(json.utf8), now: now)
        #expect(usage?.credits?.balance == nil)
        #expect(usage?.credits?.hasCredits == true)
    }

    @Test("unlimited credits mapping")
    func unlimited() {
        let json = #"{"rateLimits":{"primary":{"usedPercent":0,"windowDurationMins":300},"credits":{"unlimited":true}}}"#
        let usage = CodexAppServerParser.parse(Data(json.utf8), now: now)
        #expect(usage?.credits?.unlimited == true)
    }

    @Test("no windowDurationMins → primary falls back to 5h")
    func unknownWindow() {
        let json = #"{"rateLimits":{"primary":{"usedPercent":9}}}"#
        let usage = CodexAppServerParser.parse(Data(json.utf8), now: now)
        #expect(usage?.window(.fiveHour)?.usedPercent == 9)
    }

    @Test("no usable payload → nil", arguments: [
        Data(),                                                       // empty
        Data(#"{}"#.utf8),                                            // no rateLimits
        Data(#"{"rateLimits":null}"#.utf8),                          // explicit null
        Data(#"{"rateLimits":{"primary":null,"secondary":null}}"#.utf8), // no window
        Data(#"{"error":{"code":-32000,"message":"login required"}}"#.utf8), // RPC error shape (no result)
        Data("not json".utf8),                                       // corrupt
    ])
    func noUsable(_ data: Data) {
        #expect(CodexAppServerParser.parse(data, now: now) == nil)
    }
}

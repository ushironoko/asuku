// Ported from quota-glance Core/Tests/QuotaGlanceCoreTests/ParsingTests.swift @ 1ba693b.
// Covers the vendored Safe-tier parsers only (ClaudeStatusLineParser is replaced by QuotaMapping,
// tested separately against StatuslineData values).

import Foundation
import Testing

@testable import AsukuAppCore

@Suite("ClaudeJSONLParser")
struct ClaudeJSONLParserTests {
    @Test("sums tokens per model, ignores non-usage lines")
    func rollup() throws {
        let r = ClaudeJSONLParser.rollup(fromJSONL: try Fixture.data("claude-projects-sample.jsonl"),
                                         pricing: .default)
        #expect(r.inputTokens == 4000)
        #expect(r.outputTokens == 1500)
        #expect(r.cacheCreationInputTokens == 2000)
        #expect(r.cacheReadInputTokens == 5000)
        #expect(r.byModel.keys.contains("claude-opus-4-8"))
        #expect(r.byModel.keys.contains("claude-sonnet-4-5-20250929"))
        #expect(r.costUSD > 0)
    }

    @Test("empty input → zero rollup")
    func empty() {
        let r = ClaudeJSONLParser.rollup(fromJSONL: Data(), pricing: .default)
        #expect(r.inputTokens == 0)
        #expect(r.outputTokens == 0)
        #expect(r.costUSD == 0)
    }
}

@Suite("CodexRolloutParser")
struct CodexRolloutParserTests {
    @Test("latest token_count event wins within a file")
    func latestWins() throws {
        let usage = try #require(
            CodexRolloutParser.latestRateLimits(fromRolloutJSONL: try Fixture.data("codex-rollout-sample.jsonl"))
        )
        #expect(usage.provider == .codex)
        #expect(usage.source == .codexRollout)
        #expect(usage.window(.fiveHour)?.usedPercent == 10.0)
        #expect(usage.window(.sevenDay)?.usedPercent == 7.0)
        #expect(usage.window(.fiveHour)?.resetsAt == Date(timeIntervalSince1970: 1_772_007_546))
        #expect(usage.credits?.hasCredits == true)
        #expect(usage.credits?.balance == 42.5)
        #expect(usage.planType == "pro")
        #expect(usage.observedAt == TimeNormalization.date(fromISO8601: "2026-02-15T15:42:00.000Z"))
    }

    @Test("file with no token_count event → nil")
    func noRateLimit() throws {
        #expect(CodexRolloutParser.latestRateLimits(fromRolloutJSONL: try Fixture.data("codex-rollout-no-ratelimit.jsonl")) == nil)
    }

    @Test("newest rollout file wins across a directory (real temp-dir FS)")
    func newestFileWins() throws {
        let fs = LocalFileSystem()
        let tmp = NSTemporaryDirectory() + "asuku-codex-\(UUID().uuidString)"
        let dayA = tmp + "/2026/02/14"
        let dayB = tmp + "/2026/02/15"
        try fs.writeAtomically(try Fixture.data("codex-rollout-no-ratelimit.jsonl"),
                               to: dayA + "/rollout-old.jsonl")
        try fs.writeAtomically(try Fixture.data("codex-rollout-sample.jsonl"),
                               to: dayB + "/rollout-new.jsonl")
        let usage = try #require(CodexRolloutParser.latestUsage(sessionsDir: tmp, fs: fs))
        #expect(usage.window(.fiveHour)?.usedPercent == 10.0)
    }

    @Test("empty sessions dir → nil, no throw")
    func emptyDir() {
        let fs = LocalFileSystem()
        let tmp = NSTemporaryDirectory() + "asuku-codex-empty-\(UUID().uuidString)"
        #expect(CodexRolloutParser.latestUsage(sessionsDir: tmp, fs: fs) == nil)
    }
}

@Suite("PricingCost")
struct PricingCostTests {
    @Test("known model cost is positive and reflects token mix")
    func known() {
        let table = PricingTable.default
        let cost = table.cost(model: "claude-opus-4-8",
                              inputTokens: 1_000_000, outputTokens: 0,
                              cacheCreationTokens: 0, cacheReadTokens: 0)
        #expect(cost > 0)
    }

    @Test("unknown model → zero (policy: don't guess)")
    func unknown() {
        let table = PricingTable.default
        let cost = table.cost(model: "totally-unknown-model",
                              inputTokens: 1_000_000, outputTokens: 1_000_000,
                              cacheCreationTokens: 0, cacheReadTokens: 0)
        #expect(cost == 0)
    }

    @Test("longest matching family prefix wins")
    func prefixMatch() {
        let table = PricingTable.default
        // "claude-opus-4-8-..." matches the "claude-opus-4" family.
        let opus = table.cost(model: "claude-opus-4-8-20260101",
                              inputTokens: 1_000_000, outputTokens: 0,
                              cacheCreationTokens: 0, cacheReadTokens: 0)
        #expect(opus == 15)
    }
}

import Foundation
import Testing

@testable import AsukuAppCore

/// A `CodexAppServerRunning` test double: returns a fixed payload (or nil) and counts calls.
private actor FakeAppServer: CodexAppServerRunning {
    private let response: Data?
    private var callCount = 0

    init(response: Data?) { self.response = response }

    func readRateLimits() async -> Data? {
        callCount += 1
        return response
    }

    func calls() -> Int { callCount }
}

@Suite("QuotaService")
struct QuotaServiceTests {
    private let fs = LocalFileSystem()
    private let now = Date(timeIntervalSince1970: 1_772_000_000)

    private func tempDir() -> String {
        NSTemporaryDirectory() + "asuku-svc-\(UUID().uuidString)"
    }

    private func makeService(
        codex: String,
        projects: String,
        snapshot: String,
        appServer: CodexAppServerRunning = FakeAppServer(response: nil)
    ) -> QuotaService {
        QuotaService(
            fs: fs,
            codexSessionsDir: codex,
            claudeProjectsDir: projects,
            snapshotPath: snapshot,
            costThrottle: 15 * 60,
            costBudget: QuotaReader.Budget(),
            appServer: appServer
        )
    }

    @Test("cost refresh is throttled: a second call within the window returns cached, no rescan")
    func costThrottled() async throws {
        let projects = tempDir()
        let sample = try Fixture.data("claude-projects-sample.jsonl")
        try fs.writeAtomically(sample, to: projects + "/a.jsonl")
        let service = makeService(codex: tempDir(), projects: projects, snapshot: tempDir() + "/q.json")

        let first = try #require(await service.refreshCost(now: now))

        // Add another file — a fresh scan would double the cost.
        try fs.writeAtomically(sample, to: projects + "/b.jsonl")
        let second = try #require(await service.refreshCost(now: now.addingTimeInterval(60)))
        #expect(second.costUSD == first.costUSD) // throttled → same cached value, dir not rescanned

        // force bypasses the throttle and picks up the new file.
        let forced = try #require(await service.refreshCost(now: now.addingTimeInterval(120), force: true))
        #expect(forced.costUSD > first.costUSD)
    }

    @Test("codex refresh yields an available observation from a rollout")
    func codexAvailable() async throws {
        let codex = tempDir()
        try fs.writeAtomically(try Fixture.data("codex-rollout-sample.jsonl"),
                               to: codex + "/2026/02/15/rollout-new.jsonl")
        let service = makeService(codex: codex, projects: tempDir(), snapshot: tempDir() + "/q.json")

        // Just after the rollout's own observation timestamp (2026-02-15T15:42Z) and before the
        // window reset, so it reads as fresh rather than stale.
        let freshNow = try #require(TimeNormalization.date(fromISO8601: "2026-02-15T15:43:00Z"))
        let observation = await service.refreshCodex(now: freshNow)
        #expect(observation.provider == .codex)
        #expect(observation.state == .available)
        #expect(observation.usage?.window(.fiveHour)?.usedPercent == 10.0)
    }

    @Test("codex refresh on empty dir → unavailable")
    func codexUnavailable() async {
        let service = makeService(codex: tempDir(), projects: tempDir(), snapshot: tempDir() + "/q.json")
        let observation = await service.refreshCodex(now: now)
        #expect(observation.state == .unavailable)
    }

    // MARK: - app-server preference / fallback

    /// A rate-limits `result` payload whose weekly window resets in the future (so it reads fresh).
    private func appServerResult(usedPercent: Int, resetCredits: Int) -> Data {
        let resetsAt = Int(now.timeIntervalSince1970) + 3600
        return Data(#"""
        {"rateLimits":{"primary":{"usedPercent":\#(usedPercent),"windowDurationMins":10080,"resetsAt":\#(resetsAt)}},"rateLimitResetCredits":{"availableCount":\#(resetCredits)}}
        """#.utf8)
    }

    @Test("useAppServer true → adopts the live app-server value over rollout")
    func appServerAdopted() async throws {
        let codex = tempDir()
        // A rollout also exists; the app-server value must win.
        try fs.writeAtomically(try Fixture.data("codex-rollout-sample.jsonl"),
                               to: codex + "/2026/02/15/rollout.jsonl")
        let fake = FakeAppServer(response: appServerResult(usedPercent: 55, resetCredits: 3))
        let service = makeService(codex: codex, projects: tempDir(), snapshot: tempDir() + "/q.json", appServer: fake)

        let obs = await service.refreshCodex(now: now, useAppServer: true)
        #expect(obs.state == .available)
        #expect(obs.usage?.source == .codexAppServer)
        #expect(obs.usage?.window(.sevenDay)?.usedPercent == 55)
        #expect(obs.usage?.resetCreditsAvailable == 3)
        #expect(await fake.calls() == 1)
    }

    @Test("useAppServer true but app-server unavailable → falls back to rollout")
    func fallbackToRollout() async throws {
        let codex = tempDir()
        try fs.writeAtomically(try Fixture.data("codex-rollout-sample.jsonl"),
                               to: codex + "/2026/02/15/rollout.jsonl")
        let fake = FakeAppServer(response: nil) // e.g. not logged in / timed out
        let service = makeService(codex: codex, projects: tempDir(), snapshot: tempDir() + "/q.json", appServer: fake)

        let freshNow = try #require(TimeNormalization.date(fromISO8601: "2026-02-15T15:43:00Z"))
        let obs = await service.refreshCodex(now: freshNow, useAppServer: true)
        #expect(obs.usage?.source == .codexRollout)
        #expect(obs.usage?.window(.fiveHour)?.usedPercent == 10.0)
        #expect(await fake.calls() == 1) // it was attempted before falling back
    }

    @Test("useAppServer false → app-server is never called, rollout is used")
    func appServerNotCalledWhenDisabled() async throws {
        let codex = tempDir()
        try fs.writeAtomically(try Fixture.data("codex-rollout-sample.jsonl"),
                               to: codex + "/2026/02/15/rollout.jsonl")
        let fake = FakeAppServer(response: appServerResult(usedPercent: 99, resetCredits: 1))
        let service = makeService(codex: codex, projects: tempDir(), snapshot: tempDir() + "/q.json", appServer: fake)

        let freshNow = try #require(TimeNormalization.date(fromISO8601: "2026-02-15T15:43:00Z"))
        let obs = await service.refreshCodex(now: freshNow, useAppServer: false)
        #expect(obs.usage?.source == .codexRollout) // not the app-server's 99%
        #expect(await fake.calls() == 0)
    }

    /// Live end-to-end through the production wiring (QuotaService → real ProcessCodexAppServer →
    /// installed codex). Skipped unless ASUKU_LIVE_CODEX=1 (needs a logged-in codex).
    @Test("live: QuotaService reads account-wide rate limits via the real app-server",
          .enabled(if: ProcessInfo.processInfo.environment["ASUKU_LIVE_CODEX"] == "1"))
    func liveQuotaServiceAppServer() async throws {
        let service = QuotaService(
            fs: fs,
            codexSessionsDir: tempDir(),
            claudeProjectsDir: tempDir(),
            snapshotPath: tempDir() + "/q.json"
            // default appServer: ProcessCodexAppServer()
        )
        let obs = await service.refreshCodex(now: Date(), useAppServer: true)
        #expect(obs.usage?.source == .codexAppServer)
        #expect(obs.usage?.provider == .codex)
        #expect(!(obs.usage?.windows.isEmpty ?? true))
    }

    @Test("after shutdown, app-server is not spawned even when requested")
    func noSpawnAfterShutdown() async throws {
        let codex = tempDir()
        try fs.writeAtomically(try Fixture.data("codex-rollout-sample.jsonl"),
                               to: codex + "/2026/02/15/rollout.jsonl")
        let fake = FakeAppServer(response: appServerResult(usedPercent: 55, resetCredits: 3))
        let service = makeService(codex: codex, projects: tempDir(), snapshot: tempDir() + "/q.json", appServer: fake)

        await service.cancelInFlight() // stop
        let freshNow = try #require(TimeNormalization.date(fromISO8601: "2026-02-15T15:43:00Z"))
        let obs = await service.refreshCodex(now: freshNow, useAppServer: true)
        #expect(obs.usage?.source == .codexRollout)
        #expect(await fake.calls() == 0)
    }

    @Test("persisted snapshot round-trips")
    func persistRoundTrip() async throws {
        let path = tempDir() + "/quota.json"
        let service = makeService(codex: tempDir(), projects: tempDir(), snapshot: path)

        let snapshot = QuotaSnapshot(
            claude: ProviderUsage(provider: .claude, windows: [RateWindow(kind: .fiveHour, usedPercent: 23.5)]),
            claudeObservedAt: now,
            costEstimate: CostEstimate(costUSD: 4.2, computedAt: now, unknownModelCount: 0, pricingVersion: "v1")
        )
        await service.persist(snapshot)
        let loaded = try #require(await service.loadPersistedSnapshot())
        #expect(loaded.claude?.window(.fiveHour)?.usedPercent == 23.5)
        #expect(loaded.costEstimate?.costUSD == 4.2)
    }

    @Test("loadPersistedSnapshot returns nil when no file exists")
    func loadMissing() async {
        let service = makeService(codex: tempDir(), projects: tempDir(), snapshot: tempDir() + "/none.json")
        #expect(await service.loadPersistedSnapshot() == nil)
    }
}

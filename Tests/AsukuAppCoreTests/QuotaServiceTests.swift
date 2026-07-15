import Foundation
import Testing

@testable import AsukuAppCore

@Suite("QuotaService")
struct QuotaServiceTests {
    private let fs = LocalFileSystem()
    private let now = Date(timeIntervalSince1970: 1_772_000_000)

    private func tempDir() -> String {
        NSTemporaryDirectory() + "asuku-svc-\(UUID().uuidString)"
    }

    private func makeService(codex: String, projects: String, snapshot: String) -> QuotaService {
        QuotaService(
            fs: fs,
            codexSessionsDir: codex,
            claudeProjectsDir: projects,
            snapshotPath: snapshot,
            costThrottle: 15 * 60,
            costBudget: QuotaReader.Budget()
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

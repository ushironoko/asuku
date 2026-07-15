import AsukuShared
import Foundation
import Testing

@testable import AsukuAppCore

@Suite("QuotaSelection")
struct QuotaSelectionTests {
    private func session(id: String, five: Double?, at: Date) -> QuotaSelection.SessionStatusline {
        let limits = five.map { RateLimits(fiveHour: RateLimitWindow(usedPercentage: $0)) }
        return QuotaSelection.SessionStatusline(
            statusline: StatuslineData(sessionId: id, rateLimits: limits),
            lastUpdated: at
        )
    }

    private let base = Date(timeIntervalSince1970: 1_772_000_000)

    @Test("newest session with windows wins")
    func newestWins() {
        let sessions = [
            session(id: "old", five: 10, at: base),
            session(id: "new", five: 55, at: base.addingTimeInterval(60)),
        ]
        let result = QuotaSelection.selectAccountQuota(
            from: sessions, previous: .neverObserved(.claude), now: base.addingTimeInterval(120)
        )
        #expect(result.usage?.window(.fiveHour)?.usedPercent == 55)
        #expect(result.sourceSessionId == "new")
        #expect(result.state == .available)
    }

    @Test("out-of-order input still picks newest timestamp")
    func outOfOrder() {
        let sessions = [
            session(id: "new", five: 55, at: base.addingTimeInterval(60)),
            session(id: "old", five: 10, at: base),
        ]
        let result = QuotaSelection.selectAccountQuota(
            from: sessions, previous: .neverObserved(.claude), now: base.addingTimeInterval(120)
        )
        #expect(result.sourceSessionId == "new")
    }

    @Test("newer session without rate_limits does NOT erase previous value")
    func missingDoesNotErase() {
        let previous = QuotaObservation(
            provider: .claude, state: .available,
            usage: ProviderUsage(provider: .claude, windows: [RateWindow(kind: .fiveHour, usedPercent: 33)]),
            observedAt: base
        )
        // Only sessions present now have no rate_limits at all.
        let sessions = [session(id: "s1", five: nil, at: base.addingTimeInterval(300))]
        let result = QuotaSelection.selectAccountQuota(
            from: sessions, previous: previous, now: base.addingTimeInterval(360)
        )
        #expect(result.usage?.window(.fiveHour)?.usedPercent == 33) // preserved
    }

    @Test("no candidates + never observed → stays neverObserved")
    func noCandidatesNeverObserved() {
        let result = QuotaSelection.selectAccountQuota(
            from: [session(id: "s1", five: nil, at: base)],
            previous: .neverObserved(.claude), now: base
        )
        #expect(result.state == .neverObserved)
    }

    @Test("window past its reset → stale")
    func pastResetIsStale() {
        let resetInPast = base.addingTimeInterval(-10).timeIntervalSince1970
        let sessions = [
            QuotaSelection.SessionStatusline(
                statusline: StatuslineData(
                    sessionId: "s1",
                    rateLimits: RateLimits(fiveHour: RateLimitWindow(usedPercentage: 40, resetsAt: resetInPast))
                ),
                lastUpdated: base
            )
        ]
        let result = QuotaSelection.selectAccountQuota(
            from: sessions, previous: .neverObserved(.claude), now: base
        )
        #expect(result.state == .stale)
    }

    @Test("observation older than TTL → stale")
    func olderThanTTLIsStale() {
        let sessions = [session(id: "s1", five: 40, at: base)]
        let result = QuotaSelection.selectAccountQuota(
            from: sessions, previous: .neverObserved(.claude),
            now: base.addingTimeInterval(20 * 60), staleAfter: 15 * 60
        )
        #expect(result.state == .stale)
    }

    @Test("does not regress to an older observation than currently held")
    func noRegress() {
        let previous = QuotaObservation(
            provider: .claude, state: .available,
            usage: ProviderUsage(provider: .claude, windows: [RateWindow(kind: .fiveHour, usedPercent: 80)]),
            observedAt: base.addingTimeInterval(100)
        )
        // A candidate exists but is older than what we already hold.
        let sessions = [session(id: "stale", five: 20, at: base)]
        let result = QuotaSelection.selectAccountQuota(
            from: sessions, previous: previous, now: base.addingTimeInterval(120)
        )
        #expect(result.usage?.window(.fiveHour)?.usedPercent == 80) // kept the newer previous
    }
}

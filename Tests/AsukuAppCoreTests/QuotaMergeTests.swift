import Foundation
import Testing

@testable import AsukuAppCore

@Suite("QuotaMerge")
struct QuotaMergeTests {
    private let now = Date(timeIntervalSince1970: 1_772_000_000)

    private func available(_ percent: Double, at: Date) -> QuotaObservation {
        QuotaObservation(
            provider: .codex,
            state: .available,
            usage: ProviderUsage(provider: .codex, windows: [RateWindow(kind: .fiveHour, usedPercent: percent)]),
            observedAt: at
        )
    }

    @Test("incoming available replaces previous")
    func adoptIncoming() {
        let result = QuotaMerge.merge(previous: available(10, at: now), incoming: available(55, at: now), now: now)
        #expect(result.usage?.window(.fiveHour)?.usedPercent == 55)
    }

    @Test("incoming unavailable does NOT erase a held value")
    func keepPrevious() {
        let previous = available(33, at: now)
        let incoming = QuotaObservation(provider: .codex, state: .unavailable)
        let result = QuotaMerge.merge(previous: previous, incoming: incoming, now: now)
        #expect(result.usage?.window(.fiveHour)?.usedPercent == 33)
    }

    @Test("held value decays to stale past the TTL when nothing new arrives")
    func decayToStale() {
        let previous = available(33, at: now)
        let incoming = QuotaObservation(provider: .codex, state: .unavailable)
        let result = QuotaMerge.merge(previous: previous, incoming: incoming, now: now.addingTimeInterval(20 * 60))
        #expect(result.state == .stale)
        #expect(result.usage?.window(.fiveHour)?.usedPercent == 33)
    }

    @Test("no previous value → surface incoming unavailable")
    func surfaceUnavailable() {
        let result = QuotaMerge.merge(
            previous: .neverObserved(.codex),
            incoming: QuotaObservation(provider: .codex, state: .unavailable),
            now: now
        )
        #expect(result.state == .unavailable)
    }
}

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

    @Test("newer incoming replaces an older held value")
    func newerReplaces() {
        let older = available(10, at: now.addingTimeInterval(-3600))
        let newer = available(55, at: now)
        let result = QuotaMerge.merge(previous: older, incoming: newer, now: now)
        #expect(result.usage?.window(.fiveHour)?.usedPercent == 55)
    }

    @Test("older incoming does NOT overwrite a newer held value (stale rollout must not clobber live app-server)")
    func olderDoesNotOverwrite() {
        let liveAppServer = QuotaObservation(
            provider: .codex,
            state: .available,
            usage: ProviderUsage(
                provider: .codex,
                windows: [RateWindow(kind: .sevenDay, usedPercent: 42)],
                source: .codexAppServer,
                observedAt: now,
                resetCreditsAvailable: 4
            ),
            observedAt: now
        )
        let olderRollout = QuotaObservation(
            provider: .codex,
            state: .available,
            usage: ProviderUsage(
                provider: .codex,
                windows: [RateWindow(kind: .sevenDay, usedPercent: 30)],
                source: .codexRollout,
                observedAt: now.addingTimeInterval(-3600)
            ),
            observedAt: now.addingTimeInterval(-3600)
        )
        let result = QuotaMerge.merge(previous: liveAppServer, incoming: olderRollout, now: now)
        #expect(result.usage?.window(.sevenDay)?.usedPercent == 42)
        #expect(result.usage?.source == .codexAppServer)
        #expect(result.usage?.resetCreditsAvailable == 4)
    }
}

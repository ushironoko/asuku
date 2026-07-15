import AsukuShared
import Foundation

/// Picks the account-wide Claude quota from the active sessions' statuslines.
///
/// Claude quota is account-wide but arrives per-session via the statusline hook. We pick the newest
/// session that actually carries rate windows. Critically, a newer statusline that lacks
/// `rate_limits` (e.g. before the first API response) does NOT erase a previously observed value —
/// it keeps `previous` and only re-evaluates its freshness.
public enum QuotaSelection {
    public struct SessionStatusline: Sendable {
        public var statusline: StatuslineData
        public var lastUpdated: Date
        public init(statusline: StatuslineData, lastUpdated: Date) {
            self.statusline = statusline
            self.lastUpdated = lastUpdated
        }
    }

    public static func selectAccountQuota(
        from sessions: [SessionStatusline],
        previous: QuotaObservation,
        now: Date,
        staleAfter: TimeInterval = 15 * 60
    ) -> QuotaObservation {
        // Consider only statuslines that yield usable Claude windows, newest first (by timestamp,
        // not arrival order).
        let candidates = sessions
            .map { (usage: ProviderUsage.fromClaudeStatusline($0.statusline),
                    at: $0.lastUpdated,
                    sessionId: $0.statusline.sessionId) }
            .filter { $0.usage.hasRateData }
            .sorted { $0.at > $1.at }

        guard let best = candidates.first else {
            // No fresh windows anywhere: keep the last-known value, re-evaluate staleness.
            return previous.reevaluatedFreshness(now: now, staleAfter: staleAfter)
        }

        // Don't regress to an older observation than we already hold.
        if let previousAt = previous.observedAt, best.at < previousAt {
            return previous.reevaluatedFreshness(now: now, staleAfter: staleAfter)
        }

        return QuotaObservation(
            provider: .claude,
            state: QuotaObservation.freshnessState(
                usage: best.usage, observedAt: best.at, now: now, staleAfter: staleAfter
            ),
            usage: best.usage,
            observedAt: best.at,
            sourceSessionId: best.sessionId
        )
    }
}

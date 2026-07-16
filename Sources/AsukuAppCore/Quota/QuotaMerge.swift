import Foundation

/// Merges a freshly read quota observation with the previously held one, so a transient "no data"
/// read never erases a still-useful value (the same "missing does not erase" rule the Claude
/// selection uses, applied to source-driven providers like Codex).
///
/// The merge is **timestamp-aware**: a strictly older incoming observation never replaces a newer
/// held one. This matters once Codex has two sources — the on-demand `account/rateLimits/read`
/// (observed at "now") and the rollout tail-scan (observed at the last CLI turn). Without the guard,
/// an app-server failure that falls back to an older rollout read would clobber the fresher live
/// value (and drop app-server-only fields such as `resetCreditsAvailable`).
public enum QuotaMerge {
    public static func merge(
        previous: QuotaObservation,
        incoming: QuotaObservation,
        now: Date,
        staleAfter: TimeInterval = 15 * 60
    ) -> QuotaObservation {
        // Incoming carries a usable value → adopt it, unless it is strictly OLDER than the value we
        // already hold (in which case keep ours and only decay its freshness).
        if incoming.usage != nil, incoming.state == .available || incoming.state == .stale {
            if previous.usage != nil,
               let previousAt = previous.observedAt,
               let incomingAt = incoming.observedAt,
               incomingAt < previousAt {
                return previous.reevaluatedFreshness(now: now, staleAfter: staleAfter)
            }
            return incoming
        }
        // Incoming has no usable value but we already hold one → keep ours, decay freshness only.
        if previous.usage != nil {
            return previous.reevaluatedFreshness(now: now, staleAfter: staleAfter)
        }
        // Neither holds a value → surface incoming's state (unavailable / neverObserved / error).
        return incoming
    }
}

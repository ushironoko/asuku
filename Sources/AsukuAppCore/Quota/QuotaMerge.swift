import Foundation

/// Merges a freshly read quota observation with the previously held one, so a transient "no data"
/// read never erases a still-useful value (the same "missing does not erase" rule the Claude
/// selection uses, applied to source-driven providers like Codex).
public enum QuotaMerge {
    public static func merge(
        previous: QuotaObservation,
        incoming: QuotaObservation,
        now: Date,
        staleAfter: TimeInterval = 15 * 60
    ) -> QuotaObservation {
        // Incoming carries a usable value → adopt it.
        if incoming.usage != nil, incoming.state == .available || incoming.state == .stale {
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

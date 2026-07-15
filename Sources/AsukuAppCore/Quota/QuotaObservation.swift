import Foundation

// MARK: - Quota availability / freshness state

/// The availability of a provider's quota, so the UI can distinguish "never observed" from
/// "temporarily unavailable" from "stale (last-known)" — instead of collapsing everything to nil.
public enum QuotaState: Sendable, Equatable {
    /// Never seen any quota for this provider (no statusline yet / no rollout).
    case neverObserved
    /// Fresh, valid quota.
    case available
    /// Last-known valid quota, but it may be out of date (past reset, or older than the TTL).
    case stale
    /// The source exists but reports no quota (e.g. non-subscription / API-key account, empty logs).
    case unavailable
    /// A read/parse error occurred.
    case error(String)
}

/// A provider's quota observation, carrying availability and freshness alongside the usage value.
public struct QuotaObservation: Sendable, Equatable {
    public var provider: Provider
    public var state: QuotaState
    /// The usage value — present for `.available` and `.stale`.
    public var usage: ProviderUsage?
    /// When this snapshot was observed (distinct from a window's `resetsAt`).
    public var observedAt: Date?
    /// The session that produced this observation (Claude only), for provenance display.
    public var sourceSessionId: String?

    public init(
        provider: Provider,
        state: QuotaState = .neverObserved,
        usage: ProviderUsage? = nil,
        observedAt: Date? = nil,
        sourceSessionId: String? = nil
    ) {
        self.provider = provider
        self.state = state
        self.usage = usage
        self.observedAt = observedAt
        self.sourceSessionId = sourceSessionId
    }

    public static func neverObserved(_ provider: Provider) -> QuotaObservation {
        QuotaObservation(provider: provider, state: .neverObserved)
    }

    /// Derive availability/freshness for a freshly read usage value.
    /// A window past its `resetsAt`, or an observation older than `staleAfter`, is `.stale`.
    public static func freshnessState(
        usage: ProviderUsage,
        observedAt: Date,
        now: Date,
        staleAfter: TimeInterval
    ) -> QuotaState {
        guard usage.hasRateData else { return .unavailable }
        let anyWindowReset = usage.windows.contains { window in
            if let reset = window.resetsAt { return now >= reset }
            return false
        }
        if anyWindowReset { return .stale }
        if now.timeIntervalSince(observedAt) >= staleAfter { return .stale }
        return .available
    }

    /// Re-evaluate freshness of an existing observation without changing its value. `.available`
    /// may decay to `.stale`; `.neverObserved`/`.unavailable`/`.error` are left untouched.
    public func reevaluatedFreshness(now: Date, staleAfter: TimeInterval) -> QuotaObservation {
        guard let usage, let observedAt, state == .available || state == .stale else { return self }
        var copy = self
        copy.state = Self.freshnessState(usage: usage, observedAt: observedAt, now: now, staleAfter: staleAfter)
        return copy
    }
}

// MARK: - Historical cost estimate (with provenance)

/// A local, offline token-cost estimate over Claude session logs. Separate from the statusline's
/// measured session cost — this is an estimate across all local projects and is labeled as such.
public struct CostEstimate: Sendable, Codable, Equatable {
    public var costUSD: Double
    /// When this estimate was computed.
    public var computedAt: Date
    /// Number of distinct models seen whose price was unknown (excluded from the total).
    public var unknownModelCount: Int
    /// Version string of the pricing table used.
    public var pricingVersion: String
    /// True when the scan hit a budget cap before reading every file (the total is a lower bound).
    public var truncated: Bool

    public init(
        costUSD: Double,
        computedAt: Date,
        unknownModelCount: Int,
        pricingVersion: String,
        truncated: Bool = false
    ) {
        self.costUSD = costUSD
        self.computedAt = computedAt
        self.unknownModelCount = unknownModelCount
        self.pricingVersion = pricingVersion
        self.truncated = truncated
    }
}

// MARK: - Persisted snapshot (low-sensitivity)

/// The last-known valid quota persisted to disk so the tab shows something on launch (as `.stale`).
/// Deliberately holds only percentages/resets/cost metadata — never prompts or transcript content.
public struct QuotaSnapshot: Sendable, Codable, Equatable {
    public var claude: ProviderUsage?
    public var claudeObservedAt: Date?
    public var codex: ProviderUsage?
    public var codexObservedAt: Date?
    public var costEstimate: CostEstimate?

    public init(
        claude: ProviderUsage? = nil,
        claudeObservedAt: Date? = nil,
        codex: ProviderUsage? = nil,
        codexObservedAt: Date? = nil,
        costEstimate: CostEstimate? = nil
    ) {
        self.claude = claude
        self.claudeObservedAt = claudeObservedAt
        self.codex = codex
        self.codexObservedAt = codexObservedAt
        self.costEstimate = costEstimate
    }
}

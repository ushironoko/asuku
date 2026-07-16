// Vendored from quota-glance (github.com/ushironoko/quota-glance) @ 1ba693b, MIT License.
// Upstream: Core/Sources/QGModels/ProviderUsage.swift.
// Flattened into AsukuAppCore (QG module split dropped) for the Quota tab integration.

import Foundation

/// Usage for one provider, assembled from one or more data sources.
public struct ProviderUsage: Sendable, Codable, Equatable, Hashable {
    public var provider: Provider
    public var windows: [RateWindow]
    public var credits: Credits?
    public var planType: String?
    /// Estimated spend in USD, when derivable from local token logs (Claude JSONL).
    public var costUSD: Double?
    /// The source that produced the rate windows.
    public var source: DataSource?
    /// When the underlying data was produced by the provider/CLI (for freshness display).
    public var observedAt: Date?
    /// Number of available Codex rate-limit reset credits, when the source exposes it
    /// (`codex app-server` `rateLimitResetCredits.availableCount`). Nil for sources that don't.
    public var resetCreditsAvailable: Int?

    public init(
        provider: Provider,
        windows: [RateWindow] = [],
        credits: Credits? = nil,
        planType: String? = nil,
        costUSD: Double? = nil,
        source: DataSource? = nil,
        observedAt: Date? = nil,
        resetCreditsAvailable: Int? = nil
    ) {
        self.provider = provider
        self.windows = windows
        self.credits = credits
        self.planType = planType
        self.costUSD = costUSD
        self.source = source
        self.observedAt = observedAt
        self.resetCreditsAvailable = resetCreditsAvailable
    }

    public func window(_ kind: RateWindow.Kind) -> RateWindow? {
        windows.first { $0.kind == kind }
    }

    /// Whether this provider has any rate-window data at all.
    public var hasRateData: Bool { !windows.isEmpty }
}

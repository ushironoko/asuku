import AsukuShared
import Foundation

/// Maps the Claude Code statusline `rate_limits` (already decoded into `StatuslineData`) into a
/// `ProviderUsage`. This replaces quota-glance's `ClaudeStatusLineParser`, which parsed raw JSON;
/// here the input is a Swift value (the decode boundary is owned by AsukuShared).
extension ProviderUsage {
    /// Build a Claude `ProviderUsage` from a statusline payload.
    /// A window is emitted only when its `used_percentage` is present and finite (clamped 0...100
    /// by `RateWindow.init`). The statusline's measured session cost is carried through as `costUSD`.
    public static func fromClaudeStatusline(_ statusline: StatuslineData) -> ProviderUsage {
        var windows: [RateWindow] = []
        if let limits = statusline.rateLimits {
            if let window = makeWindow(kind: .fiveHour, from: limits.fiveHour) {
                windows.append(window)
            }
            if let window = makeWindow(kind: .sevenDay, from: limits.sevenDay) {
                windows.append(window)
            }
        }
        return ProviderUsage(
            provider: .claude,
            windows: windows,
            costUSD: statusline.cost?.totalCostUsd,
            source: .claudeStatusLine
        )
    }

    private static func makeWindow(kind: RateWindow.Kind, from window: RateLimitWindow?) -> RateWindow? {
        guard let percent = window?.usedPercentage, percent.isFinite else { return nil }
        let resetsAt = window?.resetsAt
            .flatMap { $0.isFinite ? $0 : nil }
            .map(TimeNormalization.date(fromEpochSeconds:))
        return RateWindow(kind: kind, usedPercent: percent, resetsAt: resetsAt)
    }
}

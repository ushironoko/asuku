import AsukuShared
import Foundation
import Testing

@testable import AsukuAppCore

/// Owns the StatuslineData(value) → ProviderUsage mapping boundary. The JSON → StatuslineData
/// decode boundary is tested in AsukuSharedTests (no duplication here — inputs are Swift values).
@Suite("QuotaMapping")
struct QuotaMappingTests {
    private func statusline(
        five: RateLimitWindow? = nil,
        seven: RateLimitWindow? = nil,
        cost: Double? = nil
    ) -> StatuslineData {
        StatuslineData(
            cost: cost.map { CostInfo(totalCostUsd: $0) },
            rateLimits: (five == nil && seven == nil) ? nil : RateLimits(fiveHour: five, sevenDay: seven)
        )
    }

    @Test("full rate_limits + cost → both windows, cost carried, source is statusline")
    func full() {
        let s = statusline(
            five: RateLimitWindow(usedPercentage: 23.5, resetsAt: 1_772_007_546),
            seven: RateLimitWindow(usedPercentage: 41.2, resetsAt: 1_772_522_331),
            cost: 1.2345
        )
        let usage = ProviderUsage.fromClaudeStatusline(s)
        #expect(usage.provider == .claude)
        #expect(usage.source == .claudeStatusLine)
        #expect(usage.window(.fiveHour)?.usedPercent == 23.5)
        #expect(usage.window(.fiveHour)?.resetsAt == Date(timeIntervalSince1970: 1_772_007_546))
        #expect(usage.window(.sevenDay)?.usedPercent == 41.2)
        #expect(usage.costUSD == 1.2345)
    }

    @Test("five_hour only → single window")
    func fiveOnly() {
        let usage = ProviderUsage.fromClaudeStatusline(statusline(five: RateLimitWindow(usedPercentage: 12)))
        #expect(usage.window(.fiveHour) != nil)
        #expect(usage.window(.sevenDay) == nil)
    }

    @Test("used_percentage missing → window dropped")
    func percentMissing() {
        let usage = ProviderUsage.fromClaudeStatusline(
            statusline(five: RateLimitWindow(usedPercentage: nil, resetsAt: 1_772_007_546))
        )
        #expect(usage.window(.fiveHour) == nil)
        #expect(usage.windows.isEmpty)
    }

    @Test("non-finite used_percentage excluded")
    func nonFinite() {
        let usage = ProviderUsage.fromClaudeStatusline(
            statusline(five: RateLimitWindow(usedPercentage: .infinity),
                       seven: RateLimitWindow(usedPercentage: .nan))
        )
        #expect(usage.windows.isEmpty)
    }

    @Test("used_percentage clamped to 0...100")
    func clamped() {
        let usage = ProviderUsage.fromClaudeStatusline(
            statusline(five: RateLimitWindow(usedPercentage: 150),
                       seven: RateLimitWindow(usedPercentage: -5))
        )
        #expect(usage.window(.fiveHour)?.usedPercent == 100)
        #expect(usage.window(.sevenDay)?.usedPercent == 0)
    }

    @Test("no rate_limits → empty windows, cost still carried")
    func noRateLimits() {
        let usage = ProviderUsage.fromClaudeStatusline(statusline(cost: 0.5))
        #expect(usage.windows.isEmpty)
        #expect(usage.hasRateData == false)
        #expect(usage.costUSD == 0.5)
    }
}

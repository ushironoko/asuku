import Foundation
import Testing

@testable import AsukuAppCore

@Suite("QuotaDisplay")
struct QuotaDisplayTests {
    private func usage(_ percents: [Double]) -> ProviderUsage {
        ProviderUsage(
            provider: .claude,
            windows: percents.enumerated().map { i, p in
                RateWindow(kind: i == 0 ? .fiveHour : .sevenDay, usedPercent: p)
            }
        )
    }

    @Test("nil usage → nil")
    func nilUsage() {
        #expect(QuotaDisplay.menuBarPercent(nil) == nil)
    }

    @Test("empty windows → nil")
    func emptyWindows() {
        #expect(QuotaDisplay.menuBarPercent(ProviderUsage(provider: .claude)) == nil)
    }

    @Test("single window → its rounded percent")
    func single() {
        #expect(QuotaDisplay.menuBarPercent(usage([23.5])) == 24)
        #expect(QuotaDisplay.menuBarPercent(usage([23.4])) == 23)
    }

    @Test("multiple windows → max")
    func maxOfWindows() {
        #expect(QuotaDisplay.menuBarPercent(usage([23.5, 41.2])) == 41)
    }

    @Test("level reflects the max percent")
    func level() {
        #expect(QuotaDisplay.menuBarLevel(usage([10, 20])) == .ok)
        #expect(QuotaDisplay.menuBarLevel(usage([10, 80])) == .warn)
        #expect(QuotaDisplay.menuBarLevel(usage([95, 20])) == .critical)
        #expect(QuotaDisplay.menuBarLevel(ProviderUsage(provider: .claude)) == nil)
    }
}

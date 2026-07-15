import Foundation
import InlineSnapshotTesting
import Testing

@testable import AsukuAppCore

/// Regression snapshots for the new public quota models — one `.dump` each. Behavioral coverage
/// lives in the QuotaMapping/QuotaSelection/QuotaDisplay suites; these just pin the shape.
@Suite("Quota model snapshots")
struct QuotaModelSnapshotTests {
    private let reset = Date(timeIntervalSince1970: 1_772_007_546)
    private let observed = Date(timeIntervalSince1970: 1_772_000_000)

    @Test("RateWindow dump")
    func rateWindow() {
        let window = RateWindow(kind: .fiveHour, usedPercent: 23.5, resetsAt: reset)
        assertInlineSnapshot(of: window, as: .dump) {
            """
            ▿ RateWindow
              - kind: Kind.fiveHour
              ▿ resetsAt: Optional<Date>
                - some: 2026-02-25T08:19:06Z
              - usedPercent: 23.5

            """
        }
    }

    @Test("ProviderUsage dump")
    func providerUsage() {
        let usage = ProviderUsage(
            provider: .claude,
            windows: [RateWindow(kind: .fiveHour, usedPercent: 23.5, resetsAt: reset)],
            costUSD: 1.2345,
            source: .claudeStatusLine
        )
        assertInlineSnapshot(of: usage, as: .dump) {
            """
            ▿ ProviderUsage
              ▿ costUSD: Optional<Double>
                - some: 1.2345
              - credits: Optional<Credits>.none
              - observedAt: Optional<Date>.none
              - planType: Optional<String>.none
              - provider: Provider.claude
              ▿ source: Optional<DataSource>
                - some: DataSource.claudeStatusLine
              ▿ windows: 1 element
                ▿ RateWindow
                  - kind: Kind.fiveHour
                  ▿ resetsAt: Optional<Date>
                    - some: 2026-02-25T08:19:06Z
                  - usedPercent: 23.5

            """
        }
    }

    @Test("QuotaObservation dump")
    func quotaObservation() {
        let observation = QuotaObservation(
            provider: .claude,
            state: .available,
            usage: ProviderUsage(
                provider: .claude,
                windows: [RateWindow(kind: .fiveHour, usedPercent: 23.5, resetsAt: reset)],
                source: .claudeStatusLine
            ),
            observedAt: observed,
            sourceSessionId: "sess-1"
        )
        assertInlineSnapshot(of: observation, as: .dump) {
            """
            ▿ QuotaObservation
              ▿ observedAt: Optional<Date>
                - some: 2026-02-25T06:13:20Z
              - provider: Provider.claude
              ▿ sourceSessionId: Optional<String>
                - some: "sess-1"
              - state: QuotaState.available
              ▿ usage: Optional<ProviderUsage>
                ▿ some: ProviderUsage
                  - costUSD: Optional<Double>.none
                  - credits: Optional<Credits>.none
                  - observedAt: Optional<Date>.none
                  - planType: Optional<String>.none
                  - provider: Provider.claude
                  ▿ source: Optional<DataSource>
                    - some: DataSource.claudeStatusLine
                  ▿ windows: 1 element
                    ▿ RateWindow
                      - kind: Kind.fiveHour
                      ▿ resetsAt: Optional<Date>
                        - some: 2026-02-25T08:19:06Z
                      - usedPercent: 23.5

            """
        }
    }
}

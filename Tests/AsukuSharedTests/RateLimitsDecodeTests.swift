import Foundation
import Testing

@testable import AsukuShared

/// Boundary tests for the `rate_limits` subtree added to StatuslineData.
/// This layer owns the JSON → StatuslineData decode boundary; the raw%→ProviderUsage
/// mapping boundary lives in AsukuAppCoreTests (no duplication).
@Suite("StatuslineData rate_limits decode")
struct RateLimitsDecodeTests {
    private func decode(_ json: String) throws -> StatuslineData {
        try JSONDecoder().decode(StatuslineData.self, from: Data(json.utf8))
    }

    @Test("full rate_limits → both windows with percent + reset")
    func full() throws {
        let s = try decode("""
            { "rate_limits": {
                "five_hour": { "used_percentage": 23.5, "resets_at": 1772007546 },
                "seven_day": { "used_percentage": 41.2, "resets_at": 1772522331 }
            } }
            """)
        #expect(s.rateLimits?.fiveHour?.usedPercentage == 23.5)
        #expect(s.rateLimits?.fiveHour?.resetsAt == 1_772_007_546)
        #expect(s.rateLimits?.sevenDay?.usedPercentage == 41.2)
        #expect(s.rateLimits?.sevenDay?.resetsAt == 1_772_522_331)
    }

    @Test("five_hour only → seven_day nil")
    func fiveOnly() throws {
        let s = try decode("""
            { "rate_limits": { "five_hour": { "used_percentage": 12 } } }
            """)
        #expect(s.rateLimits?.fiveHour?.usedPercentage == 12)
        #expect(s.rateLimits?.sevenDay == nil)
    }

    @Test("used_percentage missing → nil, resets preserved")
    func percentMissing() throws {
        let s = try decode("""
            { "rate_limits": { "five_hour": { "resets_at": 1772007546 } } }
            """)
        #expect(s.rateLimits?.fiveHour?.usedPercentage == nil)
        #expect(s.rateLimits?.fiveHour?.resetsAt == 1_772_007_546)
    }

    @Test("resets_at missing → nil, percent preserved")
    func resetMissing() throws {
        let s = try decode("""
            { "rate_limits": { "seven_day": { "used_percentage": 41.2 } } }
            """)
        #expect(s.rateLimits?.sevenDay?.usedPercentage == 41.2)
        #expect(s.rateLimits?.sevenDay?.resetsAt == nil)
    }

    @Test("integer used_percentage decodes to Double")
    func integerPercent() throws {
        let s = try decode("""
            { "rate_limits": { "five_hour": { "used_percentage": 50 } } }
            """)
        #expect(s.rateLimits?.fiveHour?.usedPercentage == 50.0)
    }

    @Test("malformed used_percentage (string) → nil, no throw, cost survives")
    func malformedLeaf() throws {
        let s = try decode("""
            {
                "cost": { "total_cost_usd": 0.5 },
                "rate_limits": { "five_hour": { "used_percentage": "oops", "resets_at": 1772007546 } }
            }
            """)
        #expect(s.rateLimits?.fiveHour?.usedPercentage == nil)
        #expect(s.rateLimits?.fiveHour?.resetsAt == 1_772_007_546)
        #expect(s.cost?.totalCostUsd == 0.5) // sibling fields survive a malformed leaf
    }

    @Test("rate_limits absent → nil")
    func absent() throws {
        let s = try decode("""
            { "cost": { "total_cost_usd": 0.5 } }
            """)
        #expect(s.rateLimits == nil)
        #expect(s.cost?.totalCostUsd == 0.5)
    }

    @Test("rate_limits as non-object → empty, no throw, cost survives")
    func nonObject() throws {
        let s = try decode("""
            { "cost": { "total_cost_usd": 0.5 }, "rate_limits": "unexpected" }
            """)
        #expect(s.rateLimits?.fiveHour == nil)
        #expect(s.rateLimits?.sevenDay == nil)
        #expect(s.cost?.totalCostUsd == 0.5)
    }

    @Test("round-trip re-encode preserves values")
    func roundTrip() throws {
        let original = StatuslineData(
            sessionId: "s1",
            rateLimits: RateLimits(
                fiveHour: RateLimitWindow(usedPercentage: 23.5, resetsAt: 1_772_007_546),
                sevenDay: RateLimitWindow(usedPercentage: 41.2, resetsAt: nil)
            )
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StatuslineData.self, from: data)
        #expect(decoded == original)
    }

    @Test("explicit initializer defaults rateLimits to nil")
    func initializerDefault() {
        let s = StatuslineData(sessionId: "s1")
        #expect(s.rateLimits == nil)
    }
}

import Foundation
import Testing

@testable import AsukuAppCore

@Suite("SnapshotDisplay")
struct SnapshotDisplayTests {
    private let now = Date(timeIntervalSince1970: 1_772_000_000)

    @Test("level thresholds at 75 / 90")
    func level() {
        #expect(SnapshotDisplay.level(usedPercent: 10) == .ok)
        #expect(SnapshotDisplay.level(usedPercent: 75) == .warn)
        #expect(SnapshotDisplay.level(usedPercent: 89) == .warn)
        #expect(SnapshotDisplay.level(usedPercent: 90) == .critical)
    }

    @Test("compactCountdown is days-aware")
    func compactCountdown() {
        #expect(SnapshotDisplay.compactCountdown(to: now.addingTimeInterval(3 * 86400 + 4 * 3600), now: now) == "3d 4h")
        #expect(SnapshotDisplay.compactCountdown(to: now.addingTimeInterval(5 * 3600 + 12 * 60), now: now) == "5h 12m")
        #expect(SnapshotDisplay.compactCountdown(to: now.addingTimeInterval(45 * 60), now: now) == "45m")
        #expect(SnapshotDisplay.compactCountdown(to: now.addingTimeInterval(-10), now: now) == "now")
    }
}

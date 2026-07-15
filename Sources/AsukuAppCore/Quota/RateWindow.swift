// Vendored from quota-glance (github.com/ushironoko/quota-glance) @ 1ba693b, MIT License.
// Upstream: Core/Sources/QGModels/RateWindow.swift.
// Flattened into AsukuAppCore (QG module split dropped) for the Quota tab integration.

import Foundation

/// A single rate-limit window for a provider.
///
/// Both providers expose a 5-hour rolling window and a 7-day (weekly) window. Codex reports them
/// as `primary` (window_minutes 300) and `secondary` (window_minutes 10080); both map here.
public struct RateWindow: Sendable, Codable, Equatable, Hashable {
    public enum Kind: String, Sendable, Codable, Hashable {
        case fiveHour
        case sevenDay

        public var displayName: String {
            switch self {
            case .fiveHour: "5h"
            case .sevenDay: "Weekly"
            }
        }

        /// Map a provider's `window_minutes` to a window kind, using `fallback` when absent.
        /// 300 → 5h, 10080 → weekly; the ≤600 cut cleanly separates the two real windows.
        public static func from(windowMinutes: Int?, fallback: Kind) -> Kind {
            guard let minutes = windowMinutes else { return fallback }
            return minutes <= 600 ? .fiveHour : .sevenDay
        }
    }

    public var kind: Kind
    /// Consumed percentage, normalized to 0...100.
    public var usedPercent: Double
    /// When the window resets, if known.
    public var resetsAt: Date?

    public init(kind: Kind, usedPercent: Double, resetsAt: Date? = nil) {
        self.kind = kind
        self.usedPercent = usedPercent.clamped(to: 0...100)
        self.resetsAt = resetsAt
    }

    /// Remaining headroom, 0...100.
    public var remainingPercent: Double { (100 - usedPercent).clamped(to: 0...100) }

    /// Usage as a 0...1 fraction (handy for SwiftUI gauges).
    public var usedFraction: Double { usedPercent / 100 }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

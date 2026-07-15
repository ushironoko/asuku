// Vendored from quota-glance (github.com/ushironoko/quota-glance) @ 1ba693b, MIT License.
// Upstream: Core/Sources/QGSnapshot/SnapshotDisplay.swift.
// Flattened into AsukuAppCore (QG module split dropped) for the Quota tab integration.

import Foundation

public enum UsageLevel: String, Sendable, Equatable {
    case ok, warn, critical
}

/// Pure display derivations shared by the Quota tab views (keeps Views dumb).
public enum SnapshotDisplay {
    public static func level(usedPercent: Double, warnAt: Double = 75, criticalAt: Double = 90) -> UsageLevel {
        if usedPercent >= criticalAt { return .critical }
        if usedPercent >= warnAt { return .warn }
        return .ok
    }

    /// Compact human countdown: "2h 2m", "12m", or "now" once elapsed.
    public static func countdown(to date: Date, now: Date) -> String {
        let remaining = Int(date.timeIntervalSince(now))
        guard remaining > 0 else { return "now" }
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    /// Days-aware compact countdown for wide windows (e.g. the 7-day reset): "3d 4h", "5h 12m",
    /// "45m", or "now". Keeps weekly resets readable instead of showing "167h 0m".
    public static func compactCountdown(to date: Date, now: Date) -> String {
        let remaining = Int(date.timeIntervalSince(now))
        guard remaining > 0 else { return "now" }
        let days = remaining / 86400
        let hours = (remaining % 86400) / 3600
        let minutes = (remaining % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

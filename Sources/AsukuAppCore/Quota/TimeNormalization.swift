// Vendored from quota-glance (github.com/ushironoko/quota-glance) @ 1ba693b, MIT License.
// Upstream: Core/Sources/QGSupport/TimeNormalization.swift.
// Flattened into AsukuAppCore (QG module split dropped) for the Quota tab integration.

import Foundation

/// Normalizes the several `resets_at` / timestamp formats the providers emit into `Date`.
///
/// - Codex rollout & Claude statusLine: epoch **seconds** (Double).
/// - Codex rollout `timestamp`: ISO-8601 (sometimes with fractional seconds).
public enum TimeNormalization {
    public static func date(fromEpochSeconds seconds: Double) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    public static func date(fromEpochMilliseconds millis: Double) -> Date {
        Date(timeIntervalSince1970: millis / 1000)
    }

    public static func date(fromISO8601 string: String) -> Date? {
        guard !string.isEmpty else { return nil }
        // ISO8601DateFormatter is not Sendable, so build it locally (call frequency is low).
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: string) { return d }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string)
    }

    /// Smartly interpret a numeric timestamp as seconds or milliseconds.
    ///
    /// Values at/above 10^12 (~ year 33658 in seconds) are treated as milliseconds; this cleanly
    /// separates 10-digit epoch-seconds from 13-digit epoch-milliseconds for any realistic date.
    public static func resetDate(fromNumber value: Double) -> Date? {
        guard value > 0 else { return nil }
        return value >= 1_000_000_000_000 ? date(fromEpochMilliseconds: value) : date(fromEpochSeconds: value)
    }
}

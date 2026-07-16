// Vendored from quota-glance (github.com/ushironoko/quota-glance) @ 1ba693b, MIT License.
// Upstream: Core/Sources/QGParsing/CodexRolloutParser.swift.
// Flattened into AsukuAppCore (QG module split dropped) for the Quota tab integration.

import Foundation

/// Parses Codex rollout logs (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`). The newest file's
/// last `token_count` event carries authoritative 5h/weekly rate limits, obtained offline with zero
/// token cost and no subprocess. This is the *fallback* source: it only updates when the Codex CLI
/// itself runs a turn. The live, account-wide value (which also reflects usage driven through other
/// clients, e.g. pi) comes from `CodexAppServerParser` via `account/rateLimits/read` — also
/// zero-token, since only a `turn/*` spends tokens and neither path ever sends one.
public enum CodexRolloutParser {
    private struct Line: Decodable {
        struct Payload: Decodable {
            struct RateLimits: Decodable {
                struct Window: Decodable {
                    let used_percent: Double?
                    let window_minutes: Int?
                    let resets_at: Double?
                }
                struct Credits: Decodable {
                    let has_credits: Bool?
                    let unlimited: Bool?
                    let balance: Double?
                }
                let primary: Window?
                let secondary: Window?
                let credits: Credits?
                let plan_type: String?
            }
            let type: String?
            let rate_limits: RateLimits?
        }
        let timestamp: String?
        let payload: Payload?
    }

    /// Parse the latest rate limits from a single rollout file's bytes. Returns nil if no
    /// `token_count` event with rate limits is present.
    public static func latestRateLimits(fromRolloutJSONL data: Data) -> ProviderUsage? {
        let decoder = JSONDecoder()
        let newline = UInt8(ascii: "\n")
        var latest: Line?

        for slice in data.split(separator: newline, omittingEmptySubsequences: true) {
            guard
                let line = try? decoder.decode(Line.self, from: Data(slice)),
                line.payload?.type == "token_count",
                line.payload?.rate_limits != nil
            else { continue }
            latest = line // chronological file → last wins
        }

        guard let line = latest, let rl = line.payload?.rate_limits else { return nil }

        var windows: [RateWindow] = []
        if let p = rl.primary, let pct = p.used_percent {
            windows.append(RateWindow(kind: .from(windowMinutes: p.window_minutes, fallback: .fiveHour),
                                      usedPercent: pct,
                                      resetsAt: p.resets_at.map(TimeNormalization.date(fromEpochSeconds:))))
        }
        if let s = rl.secondary, let pct = s.used_percent {
            windows.append(RateWindow(kind: .from(windowMinutes: s.window_minutes, fallback: .sevenDay),
                                      usedPercent: pct,
                                      resetsAt: s.resets_at.map(TimeNormalization.date(fromEpochSeconds:))))
        }

        let credits = rl.credits.map {
            Credits(hasCredits: $0.has_credits ?? false, unlimited: $0.unlimited ?? false, balance: $0.balance)
        }
        let observedAt = line.timestamp.flatMap(TimeNormalization.date(fromISO8601:))

        return ProviderUsage(
            provider: .codex,
            windows: windows,
            credits: credits,
            planType: rl.plan_type,
            source: .codexRollout,
            observedAt: observedAt
        )
    }

    /// Find the newest rollout file under `sessionsDir` that contains rate limits and parse it.
    /// Bounded by `maxFilesToScan` (candidate files, newest first) and `maxFileBytes` (skip any
    /// single rollout file larger than this) so the scan stays cheap on a large sessions tree.
    public static func latestUsage(
        sessionsDir: String,
        fs: FileSystem,
        maxFilesToScan: Int = 8,
        maxFileBytes: UInt64 = 16 * 1024 * 1024
    ) -> ProviderUsage? {
        var scanned = 0
        for path in fs.filesRecursively(under: sessionsDir, withSuffix: ".jsonl") { // newest first
            if scanned >= maxFilesToScan { break }
            if let size = fs.fileSize(at: path), size > maxFileBytes { continue }
            scanned += 1
            if let data = try? fs.readData(at: path),
               let usage = latestRateLimits(fromRolloutJSONL: data) {
                return usage
            }
        }
        return nil
    }
}

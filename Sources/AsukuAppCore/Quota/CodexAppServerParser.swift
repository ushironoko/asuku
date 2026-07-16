import Foundation

/// Parses the `result` of a `codex app-server` `account/rateLimits/read` JSON-RPC response
/// (`GetAccountRateLimitsResponse`) into a `ProviderUsage`.
///
/// Unlike `CodexRolloutParser` (which tail-scans rollout files written only when the codex CLI runs
/// a turn), this reflects the **live, account-wide** rate limits obtained on demand — so usage from
/// any client on the account, including pi (`provider: openai-codex`), is included. The read costs
/// zero tokens (`account/*` is a metadata read; only `turn/*` spends tokens).
///
/// The JSON-RPC envelope (`{"id":1,"result":{…}}` / `{"error":{…}}`) is stripped by the transport;
/// this receives the `result` object bytes. `GetAccountRateLimitsResponse.rateLimits` is the
/// backward-compatible single-bucket snapshot ("mirrors the historical payload"), i.e. the same
/// shape `CodexRolloutParser` reads — only camelCased.
public enum CodexAppServerParser {
    private struct Response: Decodable {
        struct Snapshot: Decodable {
            struct Window: Decodable {
                let usedPercent: Double?
                let windowDurationMins: Int?
                let resetsAt: Double? // epoch seconds
            }
            struct Credits: Decodable {
                let hasCredits: Bool?
                let unlimited: Bool?
                let balance: String? // app-server sends this as a string, e.g. "0"
            }
            let primary: Window?
            let secondary: Window?
            let credits: Credits?
            let planType: String?
        }
        struct ResetCredits: Decodable {
            let availableCount: Int?
        }
        let rateLimits: Snapshot?
        let rateLimitResetCredits: ResetCredits?
    }

    /// Parse the `result` bytes into a `ProviderUsage`. `now` is the observation time (injected for
    /// determinism — the payload carries no timestamp; the read reflects the current instant).
    /// Returns nil for empty/corrupt/error payloads or when no usable rate window is present.
    public static func parse(_ data: Data, now: Date) -> ProviderUsage? {
        guard
            !data.isEmpty,
            let response = try? JSONDecoder().decode(Response.self, from: data),
            let snapshot = response.rateLimits
        else { return nil }

        var windows: [RateWindow] = []
        if let p = snapshot.primary, let pct = p.usedPercent {
            windows.append(RateWindow(kind: .from(windowMinutes: p.windowDurationMins, fallback: .fiveHour),
                                      usedPercent: pct,
                                      resetsAt: p.resetsAt.map(TimeNormalization.date(fromEpochSeconds:))))
        }
        if let s = snapshot.secondary, let pct = s.usedPercent {
            windows.append(RateWindow(kind: .from(windowMinutes: s.windowDurationMins, fallback: .sevenDay),
                                      usedPercent: pct,
                                      resetsAt: s.resetsAt.map(TimeNormalization.date(fromEpochSeconds:))))
        }
        guard !windows.isEmpty else { return nil }

        let credits = snapshot.credits.map {
            Credits(hasCredits: $0.hasCredits ?? false,
                    unlimited: $0.unlimited ?? false,
                    balance: $0.balance.flatMap(Double.init))
        }

        return ProviderUsage(
            provider: .codex,
            windows: windows,
            credits: credits,
            planType: snapshot.planType,
            source: .codexAppServer,
            observedAt: now,
            resetCreditsAvailable: response.rateLimitResetCredits?.availableCount
        )
    }
}

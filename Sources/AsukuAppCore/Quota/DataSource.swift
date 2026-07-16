// Vendored from quota-glance (github.com/ushironoko/quota-glance) @ 1ba693b, MIT License.
// Upstream: Core/Sources/QGModels/DataSource.swift (trimmed to the Safe-tier cases only —
// the undocumented/authoritative cases and Tier are intentionally omitted here).
// Flattened into AsukuAppCore (QG module split dropped) for the Quota tab integration.

import Foundation

/// Identifies which concrete Safe-tier source produced a piece of usage data.
public enum DataSource: String, Sendable, Codable, Hashable {
    case claudeStatusLine  // official (Claude Code statusLine rate_limits)
    case claudeJSONL       // local token/cost rollup
    case codexRollout      // local rollout rate_limits
    case codexAppServer    // live account-wide rate_limits via `codex app-server` account/rateLimits/read

    public var provider: Provider {
        switch self {
        case .claudeStatusLine, .claudeJSONL: .claude
        case .codexRollout, .codexAppServer: .codex
        }
    }
}

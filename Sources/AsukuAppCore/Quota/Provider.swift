// Vendored from quota-glance (github.com/ushironoko/quota-glance) @ 1ba693b, MIT License.
// Upstream: Core/Sources/QGModels/Provider.swift.
// Flattened into AsukuAppCore (QG module split dropped) for the Quota tab integration.

import Foundation

/// A subscription whose usage the Quota tab can surface.
///
/// Scope is deliberately limited to Claude.ai Pro/Max quota and Codex (ChatGPT-plan) quota.
public enum Provider: String, Sendable, Codable, CaseIterable, Hashable {
    case claude
    case codex

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }
}

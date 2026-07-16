import Foundation

/// Whether asuku reads live, account-wide Codex rate limits via `codex app-server`
/// (`account/rateLimits/read`). When enabled, this captures usage from every client on the account —
/// including pi (`provider: openai-codex`) — which the rollout tail-scan alone cannot. Falls back to
/// the rollout scan automatically when disabled, not logged in, or the `codex` binary is missing.
public struct CodexAppServerConfig: Equatable, Sendable {
    public var isEnabled: Bool

    public init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }
}

/// Stateless persistence for `CodexAppServerConfig` via UserDefaults.
///
/// `load` is **side-effect-free**: a missing key reads as the default (enabled) without writing it
/// back, so "never configured" stays distinguishable from an explicit choice and no default is
/// baked into persisted state.
public enum CodexAppServerConfigStore {
    private static let enabledKey = "codexAppServer.isEnabled"

    public static func load(from defaults: UserDefaults = .standard) -> CodexAppServerConfig {
        let isEnabled = defaults.object(forKey: enabledKey) != nil
            ? defaults.bool(forKey: enabledKey)
            : true // default ON — not persisted
        return CodexAppServerConfig(isEnabled: isEnabled)
    }

    public static func save(_ config: CodexAppServerConfig, to defaults: UserDefaults = .standard) {
        defaults.set(config.isEnabled, forKey: enabledKey)
    }
}

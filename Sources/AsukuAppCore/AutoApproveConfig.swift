import AsukuShared
import Foundation

/// Configuration for automatically approving permission requests.
/// Disabled by default because enabling it allows every requested tool to run without review.
public struct AutoApproveConfig: Equatable, Sendable {
    public var isEnabled: Bool

    public init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }

    /// Centralized policy seam for future tool- or input-specific rules.
    public func shouldApprove(_: PermissionRequestEvent) -> Bool {
        isEnabled
    }
}

/// Stateless persistence for AutoApproveConfig via UserDefaults.
public enum AutoApproveConfigStore {
    private static let enabledKey = "autoApprove.isEnabled"

    public static func load(from defaults: UserDefaults = .standard) -> AutoApproveConfig {
        AutoApproveConfig(isEnabled: defaults.bool(forKey: enabledKey))
    }

    public static func save(
        _ config: AutoApproveConfig,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(config.isEnabled, forKey: enabledKey)
    }
}

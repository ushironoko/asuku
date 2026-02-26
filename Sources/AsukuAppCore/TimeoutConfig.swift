import Foundation

/// Pure data struct for auto-timeout configuration.
/// Sendable + Equatable are automatically synthesized.
public struct TimeoutConfig: Equatable, Sendable {
    public var isEnabled: Bool
    public var timeoutSeconds: Int

    public init(
        isEnabled: Bool = true,
        timeoutSeconds: Int = 280
    ) {
        self.isEnabled = isEnabled
        self.timeoutSeconds = timeoutSeconds
    }

    /// Effective timeout value for PendingRequestManager.
    /// Returns nil when disabled (no timeout task created).
    public var effectiveTimeout: TimeInterval? {
        isEnabled ? TimeInterval(max(10, min(280, timeoutSeconds))) : nil
    }
}

/// Stateless persistence for TimeoutConfig via UserDefaults.
public enum TimeoutConfigStore {
    private static let enabledKey = "timeout.isEnabled"
    private static let secondsKey = "timeout.seconds"

    public static func load(from defaults: UserDefaults = .standard) -> TimeoutConfig {
        // UserDefaults.bool returns false for missing keys, so check existence
        let isEnabled: Bool
        if defaults.object(forKey: enabledKey) != nil {
            isEnabled = defaults.bool(forKey: enabledKey)
        } else {
            isEnabled = true
            defaults.set(true, forKey: enabledKey)
        }

        let storedSeconds = defaults.integer(forKey: secondsKey)
        let timeoutSeconds: Int
        if storedSeconds > 0 {
            timeoutSeconds = storedSeconds
        } else {
            timeoutSeconds = 280
            defaults.set(280, forKey: secondsKey)
        }

        return TimeoutConfig(
            isEnabled: isEnabled,
            timeoutSeconds: timeoutSeconds
        )
    }

    public static func save(_ config: TimeoutConfig, to defaults: UserDefaults = .standard) {
        defaults.set(config.isEnabled, forKey: enabledKey)
        defaults.set(config.timeoutSeconds, forKey: secondsKey)
    }
}

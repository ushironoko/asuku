import Foundation

/// Pure data struct for ntfy push notification configuration.
/// Sendable + Equatable are automatically synthesized.
public struct NtfyConfig: Equatable, Sendable {
    public var isEnabled: Bool
    public var topic: String
    public var serverURL: String
    public var webhookBaseURL: String
    public var webhookPort: UInt16
    public var webhookSecret: String

    public init(
        isEnabled: Bool = false,
        topic: String = "",
        serverURL: String = "https://ntfy.sh",
        webhookBaseURL: String = "",
        webhookPort: UInt16 = 8945,
        webhookSecret: String = ""
    ) {
        self.isEnabled = isEnabled
        self.topic = topic
        self.serverURL = serverURL
        self.webhookBaseURL = webhookBaseURL
        self.webhookPort = webhookPort
        self.webhookSecret = webhookSecret
    }
}

/// Stateless persistence for NtfyConfig via UserDefaults.
/// Separates data definition from side effects (disk I/O).
public enum NtfyConfigStore {
    private static let enabledKey = "ntfy.isEnabled"
    private static let topicKey = "ntfy.topic"
    private static let serverURLKey = "ntfy.serverURL"
    private static let webhookBaseURLKey = "ntfy.webhookBaseURL"
    private static let webhookPortKey = "ntfy.webhookPort"
    private static let webhookSecretKey = "ntfy.webhookSecret"

    public static func load(from defaults: UserDefaults = .standard) -> NtfyConfig {
        let isEnabled = defaults.bool(forKey: enabledKey)
        let topic = defaults.string(forKey: topicKey)
            ?? generateAndPersist(key: topicKey, value: "asuku-\(UUID().uuidString)", defaults: defaults)
        let serverURL = defaults.string(forKey: serverURLKey)
            ?? generateAndPersist(key: serverURLKey, value: "https://ntfy.sh", defaults: defaults)
        let webhookBaseURL = defaults.string(forKey: webhookBaseURLKey) ?? ""
        let storedPort = defaults.integer(forKey: webhookPortKey)
        let webhookPort: UInt16
        if storedPort > 0 {
            webhookPort = UInt16(exactly: storedPort) ?? 8945
        } else {
            webhookPort = 8945
            defaults.set(Int(8945), forKey: webhookPortKey)
        }
        let webhookSecret = defaults.string(forKey: webhookSecretKey)
            ?? generateAndPersist(key: webhookSecretKey, value: UUID().uuidString, defaults: defaults)

        return NtfyConfig(
            isEnabled: isEnabled,
            topic: topic,
            serverURL: serverURL,
            webhookBaseURL: webhookBaseURL,
            webhookPort: webhookPort,
            webhookSecret: webhookSecret
        )
    }

    public static func save(_ config: NtfyConfig, to defaults: UserDefaults = .standard) {
        defaults.set(config.isEnabled, forKey: enabledKey)
        defaults.set(config.topic, forKey: topicKey)
        defaults.set(config.serverURL, forKey: serverURLKey)
        defaults.set(config.webhookBaseURL, forKey: webhookBaseURLKey)
        defaults.set(Int(config.webhookPort), forKey: webhookPortKey)
        defaults.set(config.webhookSecret, forKey: webhookSecretKey)
    }

    /// Generate a default value, persist it, and return it.
    private static func generateAndPersist(
        key: String, value: String, defaults: UserDefaults
    ) -> String {
        defaults.set(value, forKey: key)
        return value
    }
}

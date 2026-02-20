import Foundation
import Observation

/// UserDefaults-backed configuration for ntfy push notifications
@MainActor
@Observable
final class NtfyConfig {
    private static let enabledKey = "ntfy.isEnabled"
    private static let topicKey = "ntfy.topic"
    private static let serverURLKey = "ntfy.serverURL"
    private static let webhookBaseURLKey = "ntfy.webhookBaseURL"
    private static let webhookPortKey = "ntfy.webhookPort"

    private let defaults = UserDefaults.standard

    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    var topic: String {
        didSet { defaults.set(topic, forKey: Self.topicKey) }
    }

    var serverURL: String {
        didSet { defaults.set(serverURL, forKey: Self.serverURLKey) }
    }

    var webhookBaseURL: String {
        didSet { defaults.set(webhookBaseURL, forKey: Self.webhookBaseURLKey) }
    }

    var webhookPort: UInt16 {
        didSet { defaults.set(Int(webhookPort), forKey: Self.webhookPortKey) }
    }

    init() {
        self.isEnabled = defaults.bool(forKey: Self.enabledKey)
        self.topic = defaults.string(forKey: Self.topicKey)
            ?? "asuku-\(UUID().uuidString)"
        self.serverURL = defaults.string(forKey: Self.serverURLKey)
            ?? "https://ntfy.sh"
        self.webhookBaseURL = defaults.string(forKey: Self.webhookBaseURLKey) ?? ""
        let storedPort = defaults.integer(forKey: Self.webhookPortKey)
        self.webhookPort = storedPort > 0 ? UInt16(storedPort) : 8945

        // Persist generated defaults on first launch
        if defaults.string(forKey: Self.topicKey) == nil {
            defaults.set(topic, forKey: Self.topicKey)
        }
        if defaults.string(forKey: Self.serverURLKey) == nil {
            defaults.set(serverURL, forKey: Self.serverURLKey)
        }
        if storedPort == 0 {
            defaults.set(Int(webhookPort), forKey: Self.webhookPortKey)
        }
    }
}

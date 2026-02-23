import Foundation
import InlineSnapshotTesting
import Testing

@testable import AsukuAppCore

@Suite("NtfyConfig Tests")
struct NtfyConfigTests {

    /// Creates isolated UserDefaults for each test to avoid cross-test contamination.
    private func makeDefaults() -> UserDefaults {
        let suiteName = "asuku.test.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    // MARK: - Struct basics

    @Test("default initializer produces expected values")
    func defaultInit() {
        let config = NtfyConfig()
        #expect(config.isEnabled == false)
        #expect(config.topic == "")
        #expect(config.serverURL == "https://ntfy.sh")
        #expect(config.webhookBaseURL == "")
        #expect(config.webhookPort == 8945)
        #expect(config.webhookSecret == "")
    }

    @Test("custom initializer stores all fields")
    func customInit() {
        let config = NtfyConfig(
            isEnabled: true,
            topic: "my-topic",
            serverURL: "https://my.ntfy.server",
            webhookBaseURL: "https://tunnel.example.com",
            webhookPort: 9000,
            webhookSecret: "secret-123"
        )
        #expect(config.isEnabled == true)
        #expect(config.topic == "my-topic")
        #expect(config.serverURL == "https://my.ntfy.server")
        #expect(config.webhookBaseURL == "https://tunnel.example.com")
        #expect(config.webhookPort == 9000)
        #expect(config.webhookSecret == "secret-123")
    }

    @Test("Equatable: identical configs are equal")
    func equatable() {
        let a = NtfyConfig(isEnabled: true, topic: "t", serverURL: "s", webhookBaseURL: "w", webhookPort: 80, webhookSecret: "x")
        let b = NtfyConfig(isEnabled: true, topic: "t", serverURL: "s", webhookBaseURL: "w", webhookPort: 80, webhookSecret: "x")
        #expect(a == b)
    }

    @Test("Equatable: different configs are not equal")
    func notEquatable() {
        let a = NtfyConfig(topic: "a")
        let b = NtfyConfig(topic: "b")
        #expect(a != b)
    }

    // MARK: - NtfyConfigStore

    @Test("save and load roundtrip preserves all fields")
    func saveLoadRoundtrip() {
        let defaults = makeDefaults()
        let original = NtfyConfig(
            isEnabled: true,
            topic: "roundtrip-topic",
            serverURL: "https://custom.ntfy.sh",
            webhookBaseURL: "https://tunnel.test.com",
            webhookPort: 12345,
            webhookSecret: "secret-abc-123"
        )

        NtfyConfigStore.save(original, to: defaults)
        let loaded = NtfyConfigStore.load(from: defaults)

        #expect(loaded == original)
    }

    @Test("load from empty defaults generates topic and secret")
    func loadFromEmptyDefaults() {
        let defaults = makeDefaults()
        let config = NtfyConfigStore.load(from: defaults)

        #expect(config.isEnabled == false)
        #expect(config.topic.hasPrefix("asuku-"))
        #expect(config.serverURL == "https://ntfy.sh")
        #expect(config.webhookBaseURL == "")
        #expect(config.webhookPort == 8945)
        #expect(!config.webhookSecret.isEmpty)
    }

    @Test("load persists generated defaults for subsequent loads")
    func loadPersistsDefaults() {
        let defaults = makeDefaults()
        let first = NtfyConfigStore.load(from: defaults)
        let second = NtfyConfigStore.load(from: defaults)

        // Generated topic and secret should be the same on second load
        #expect(first.topic == second.topic)
        #expect(first.webhookSecret == second.webhookSecret)
    }

    @Test("save overwrites previous values")
    func saveOverwrites() {
        let defaults = makeDefaults()

        let config1 = NtfyConfig(topic: "first")
        NtfyConfigStore.save(config1, to: defaults)

        let config2 = NtfyConfig(topic: "second")
        NtfyConfigStore.save(config2, to: defaults)

        let loaded = NtfyConfigStore.load(from: defaults)
        #expect(loaded.topic == "second")
    }

    @Test("port fallback when stored value exceeds UInt16")
    func portFallback() {
        let defaults = makeDefaults()
        // Store a port value that exceeds UInt16.max
        defaults.set(100_000, forKey: "ntfy.webhookPort")
        // Also set topic/secret to avoid generation
        defaults.set("t", forKey: "ntfy.topic")
        defaults.set("s", forKey: "ntfy.webhookSecret")

        let config = NtfyConfigStore.load(from: defaults)
        #expect(config.webhookPort == 8945) // fallback to default
    }

    // MARK: - ServerURLValidation

    @Test("HTTPS URL is valid")
    func validateHTTPS() {
        #expect(NtfyConfig.validateServerURL("https://ntfy.sh") == .valid)
    }

    @Test("HTTPS URL with port is valid")
    func validateHTTPSWithPort() {
        #expect(NtfyConfig.validateServerURL("https://ntfy.example.com:8443") == .valid)
    }

    @Test("HTTP localhost is allowed")
    func validateHTTPLocalhost() {
        #expect(NtfyConfig.validateServerURL("http://localhost:8080") == .localhost)
    }

    @Test("HTTP 127.0.0.1 is allowed")
    func validateHTTPLoopback() {
        #expect(NtfyConfig.validateServerURL("http://127.0.0.1") == .localhost)
    }

    @Test("HTTP [::1] is allowed")
    func validateHTTPIPv6Loopback() {
        #expect(NtfyConfig.validateServerURL("http://[::1]") == .localhost)
    }

    @Test("HTTP remote server is insecure")
    func validateHTTPRemote() {
        #expect(NtfyConfig.validateServerURL("http://example.com") == .insecure)
    }

    @Test("HTTP remote server with path is insecure")
    func validateHTTPRemoteWithPath() {
        #expect(NtfyConfig.validateServerURL("http://ntfy.example.com/path") == .insecure)
    }

    @Test("FTP scheme is invalid")
    func validateFTP() {
        #expect(NtfyConfig.validateServerURL("ftp://ntfy.sh") == .invalid)
    }

    @Test("Empty string is invalid")
    func validateEmpty() {
        #expect(NtfyConfig.validateServerURL("") == .invalid)
    }

    @Test("Non-URL string is invalid")
    func validateNonURL() {
        #expect(NtfyConfig.validateServerURL("not-a-url") == .invalid)
    }

    // MARK: - Snapshot

    @Test("snapshot of config dump")
    func snapshotConfig() {
        let config = NtfyConfig(
            isEnabled: true,
            topic: "test-topic",
            serverURL: "https://ntfy.sh",
            webhookBaseURL: "https://tunnel.example.com",
            webhookPort: 8945,
            webhookSecret: "abc-secret"
        )
        assertInlineSnapshot(of: config, as: .dump) {
            """
            ▿ NtfyConfig
              - isEnabled: true
              - serverURL: "https://ntfy.sh"
              - topic: "test-topic"
              - webhookBaseURL: "https://tunnel.example.com"
              - webhookPort: 8945
              - webhookSecret: "abc-secret"

            """
        }
    }
}

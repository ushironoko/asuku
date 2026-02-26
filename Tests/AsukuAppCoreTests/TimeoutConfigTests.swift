import Foundation
import InlineSnapshotTesting
import Testing

@testable import AsukuAppCore

@Suite("TimeoutConfig Tests")
struct TimeoutConfigTests {

    // MARK: - Default Values

    @Test("default values are enabled with 280s timeout")
    func defaultValues() {
        let config = TimeoutConfig()
        #expect(config.isEnabled == true)
        #expect(config.timeoutSeconds == 280)
    }

    // MARK: - effectiveTimeout

    @Test("effectiveTimeout returns seconds when enabled")
    func effectiveTimeoutEnabled() {
        let config = TimeoutConfig(isEnabled: true, timeoutSeconds: 120)
        #expect(config.effectiveTimeout == 120.0)
    }

    @Test("effectiveTimeout returns nil when disabled")
    func effectiveTimeoutDisabled() {
        let config = TimeoutConfig(isEnabled: false, timeoutSeconds: 120)
        #expect(config.effectiveTimeout == nil)
    }

    @Test("effectiveTimeout clamps below minimum to 10")
    func effectiveTimeoutClampLow() {
        let config = TimeoutConfig(isEnabled: true, timeoutSeconds: 5)
        #expect(config.effectiveTimeout == 10.0)
    }

    @Test("effectiveTimeout clamps above maximum to 280")
    func effectiveTimeoutClampHigh() {
        let config = TimeoutConfig(isEnabled: true, timeoutSeconds: 500)
        #expect(config.effectiveTimeout == 280.0)
    }

    @Test("effectiveTimeout at minimum boundary (10)")
    func effectiveTimeoutMinBoundary() {
        let config = TimeoutConfig(isEnabled: true, timeoutSeconds: 10)
        #expect(config.effectiveTimeout == 10.0)
    }

    @Test("effectiveTimeout at maximum boundary (280)")
    func effectiveTimeoutMaxBoundary() {
        let config = TimeoutConfig(isEnabled: true, timeoutSeconds: 280)
        #expect(config.effectiveTimeout == 280.0)
    }

    // MARK: - Equatable

    @Test("configs with same values are equal")
    func equatable() {
        let a = TimeoutConfig(isEnabled: true, timeoutSeconds: 120)
        let b = TimeoutConfig(isEnabled: true, timeoutSeconds: 120)
        #expect(a == b)
    }

    @Test("configs with different isEnabled are not equal")
    func notEqualEnabled() {
        let a = TimeoutConfig(isEnabled: true, timeoutSeconds: 120)
        let b = TimeoutConfig(isEnabled: false, timeoutSeconds: 120)
        #expect(a != b)
    }

    @Test("configs with different timeoutSeconds are not equal")
    func notEqualSeconds() {
        let a = TimeoutConfig(isEnabled: true, timeoutSeconds: 120)
        let b = TimeoutConfig(isEnabled: true, timeoutSeconds: 200)
        #expect(a != b)
    }

    // MARK: - UserDefaults Roundtrip

    @Test("save and load roundtrip via UserDefaults")
    func userDefaultsRoundtrip() {
        let defaults = UserDefaults(suiteName: "TimeoutConfigTests-roundtrip")!
        defer { defaults.removePersistentDomain(forName: "TimeoutConfigTests-roundtrip") }

        let config = TimeoutConfig(isEnabled: false, timeoutSeconds: 60)
        TimeoutConfigStore.save(config, to: defaults)

        let loaded = TimeoutConfigStore.load(from: defaults)
        #expect(loaded == config)
    }

    @Test("load from empty UserDefaults returns defaults")
    func loadFromEmptyDefaults() {
        let defaults = UserDefaults(suiteName: "TimeoutConfigTests-empty")!
        defer { defaults.removePersistentDomain(forName: "TimeoutConfigTests-empty") }

        let loaded = TimeoutConfigStore.load(from: defaults)
        #expect(loaded.isEnabled == true)
        #expect(loaded.timeoutSeconds == 280)
    }

    // MARK: - Store Clamping

    @Test("save clamps timeoutSeconds below minimum to 10")
    func saveClampLow() {
        let defaults = UserDefaults(suiteName: "TimeoutConfigTests-clamp-low")!
        defer { defaults.removePersistentDomain(forName: "TimeoutConfigTests-clamp-low") }

        let config = TimeoutConfig(isEnabled: true, timeoutSeconds: 3)
        TimeoutConfigStore.save(config, to: defaults)

        let loaded = TimeoutConfigStore.load(from: defaults)
        #expect(loaded.timeoutSeconds == 10)
    }

    @Test("save clamps timeoutSeconds above maximum to 280")
    func saveClampHigh() {
        let defaults = UserDefaults(suiteName: "TimeoutConfigTests-clamp-high")!
        defer { defaults.removePersistentDomain(forName: "TimeoutConfigTests-clamp-high") }

        let config = TimeoutConfig(isEnabled: true, timeoutSeconds: 999)
        TimeoutConfigStore.save(config, to: defaults)

        let loaded = TimeoutConfigStore.load(from: defaults)
        #expect(loaded.timeoutSeconds == 280)
    }

    @Test("load clamps externally modified timeoutSeconds")
    func loadClampExternallyModified() {
        let defaults = UserDefaults(suiteName: "TimeoutConfigTests-external")!
        defer { defaults.removePersistentDomain(forName: "TimeoutConfigTests-external") }

        // Simulate external modification directly in UserDefaults
        defaults.set(true, forKey: "timeout.isEnabled")
        defaults.set(500, forKey: "timeout.seconds")

        let loaded = TimeoutConfigStore.load(from: defaults)
        #expect(loaded.timeoutSeconds == 280)
    }

    // MARK: - Snapshot

    @Test("snapshot dump of TimeoutConfig")
    func snapshotConfig() {
        assertInlineSnapshot(of: TimeoutConfig(), as: .dump) {
            """
            ▿ TimeoutConfig
              - isEnabled: true
              - timeoutSeconds: 280

            """
        }

        assertInlineSnapshot(of: TimeoutConfig(isEnabled: false, timeoutSeconds: 60), as: .dump) {
            """
            ▿ TimeoutConfig
              - isEnabled: false
              - timeoutSeconds: 60

            """
        }
    }
}

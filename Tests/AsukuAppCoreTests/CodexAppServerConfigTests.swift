import Foundation
import Testing

@testable import AsukuAppCore

@Suite("CodexAppServerConfig")
struct CodexAppServerConfigTests {
    private func freshDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "asuku-test-\(UUID().uuidString)"))
    }

    @Test("missing key defaults to enabled, without persisting")
    func defaultOn() throws {
        let defaults = try freshDefaults()
        #expect(CodexAppServerConfigStore.load(from: defaults).isEnabled == true)
        // Side-effect-free load: the default must not be baked into persisted state.
        #expect(defaults.object(forKey: "codexAppServer.isEnabled") == nil)
    }

    @Test("explicit false is respected")
    func explicitFalse() throws {
        let defaults = try freshDefaults()
        CodexAppServerConfigStore.save(CodexAppServerConfig(isEnabled: false), to: defaults)
        #expect(CodexAppServerConfigStore.load(from: defaults).isEnabled == false)
    }

    @Test("round-trips true")
    func roundTripTrue() throws {
        let defaults = try freshDefaults()
        CodexAppServerConfigStore.save(CodexAppServerConfig(isEnabled: true), to: defaults)
        #expect(CodexAppServerConfigStore.load(from: defaults).isEnabled == true)
    }
}

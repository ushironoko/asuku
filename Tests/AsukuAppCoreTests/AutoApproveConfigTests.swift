import Foundation
import Testing

@testable import AsukuAppCore
@testable import AsukuShared

@Suite("AutoApproveConfig Tests")
struct AutoApproveConfigTests {
    @Test("auto-approve is disabled by default")
    func defaultDisabled() {
        #expect(AutoApproveConfig().isEnabled == false)
    }

    @Test("disabled config does not approve a request")
    func disabledDoesNotApprove() {
        let config = AutoApproveConfig(isEnabled: false)
        #expect(config.shouldApprove(makeEvent()) == false)
    }

    @Test("enabled config approves a request")
    func enabledApproves() {
        let config = AutoApproveConfig(isEnabled: true)
        #expect(config.shouldApprove(makeEvent()) == true)
    }

    @Test("save and load roundtrip via UserDefaults")
    func userDefaultsRoundtrip() {
        let suiteName = "AutoApproveConfigTests-roundtrip"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        AutoApproveConfigStore.save(AutoApproveConfig(isEnabled: true), to: defaults)

        #expect(AutoApproveConfigStore.load(from: defaults).isEnabled == true)
    }

    @Test("empty UserDefaults keeps auto-approve disabled")
    func emptyDefaultsDisabled() {
        let suiteName = "AutoApproveConfigTests-empty"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(AutoApproveConfigStore.load(from: defaults).isEnabled == false)
    }

    private func makeEvent() -> PermissionRequestEvent {
        PermissionRequestEvent(
            requestId: "request-1",
            sessionId: "session-1",
            toolName: "Bash",
            toolInput: ["command": .string("echo test")],
            cwd: "/tmp"
        )
    }
}

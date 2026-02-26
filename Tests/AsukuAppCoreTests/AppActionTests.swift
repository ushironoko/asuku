import AsukuShared
import InlineSnapshotTesting
import Testing

@testable import AsukuAppCore

@Suite("AppAction Tests")
struct AppActionTests {

    // MARK: - Equatable

    @Test("resolveRequest actions with same values are equal")
    func resolveRequestEqual() {
        let a = AppAction.resolveRequest(requestId: "req-1", decision: .allow)
        let b = AppAction.resolveRequest(requestId: "req-1", decision: .allow)
        #expect(a == b)
    }

    @Test("resolveRequest actions with different requestIds are not equal")
    func resolveRequestDifferentId() {
        let a = AppAction.resolveRequest(requestId: "req-1", decision: .allow)
        let b = AppAction.resolveRequest(requestId: "req-2", decision: .allow)
        #expect(a != b)
    }

    @Test("resolveRequest actions with different decisions are not equal")
    func resolveRequestDifferentDecision() {
        let a = AppAction.resolveRequest(requestId: "req-1", decision: .allow)
        let b = AppAction.resolveRequest(requestId: "req-1", decision: .deny)
        #expect(a != b)
    }

    @Test("ntfyConfigChanged actions are equal")
    func ntfyConfigChangedEqual() {
        #expect(AppAction.ntfyConfigChanged == AppAction.ntfyConfigChanged)
    }

    @Test("timeoutConfigChanged actions are equal")
    func timeoutConfigChangedEqual() {
        #expect(AppAction.timeoutConfigChanged == AppAction.timeoutConfigChanged)
    }

    @Test("stop actions are equal")
    func stopEqual() {
        #expect(AppAction.stop == AppAction.stop)
    }

    @Test("different action cases are not equal")
    func differentCasesNotEqual() {
        let resolve = AppAction.resolveRequest(requestId: "r", decision: .allow)
        let ntfyChanged = AppAction.ntfyConfigChanged
        let timeoutChanged = AppAction.timeoutConfigChanged
        let stop = AppAction.stop

        #expect(resolve != ntfyChanged)
        #expect(resolve != timeoutChanged)
        #expect(resolve != stop)
        #expect(ntfyChanged != timeoutChanged)
        #expect(ntfyChanged != stop)
        #expect(timeoutChanged != stop)
    }

    // MARK: - Exhaustive switch

    @Test("exhaustive switch handles all cases")
    func exhaustiveSwitch() {
        let actions: [AppAction] = [
            .resolveRequest(requestId: "r1", decision: .allow),
            .resolveRequest(requestId: "r2", decision: .deny),
            .ntfyConfigChanged,
            .timeoutConfigChanged,
            .stop,
        ]

        var descriptions: [String] = []
        for action in actions {
            switch action {
            case .resolveRequest(let id, let decision):
                descriptions.append("resolve(\(id), \(decision.rawValue))")
            case .ntfyConfigChanged:
                descriptions.append("ntfyConfigChanged")
            case .timeoutConfigChanged:
                descriptions.append("timeoutConfigChanged")
            case .stop:
                descriptions.append("stop")
            }
        }

        assertInlineSnapshot(of: descriptions.joined(separator: "\n"), as: .lines) {
            """
            resolve(r1, allow)
            resolve(r2, deny)
            ntfyConfigChanged
            timeoutConfigChanged
            stop
            """
        }
    }

    // MARK: - Snapshot

    @Test("snapshot dump of all action cases")
    func snapshotAllCases() {
        assertInlineSnapshot(
            of: AppAction.resolveRequest(requestId: "req-123", decision: .allow), as: .dump
        ) {
            """
            ▿ AppAction
              ▿ resolveRequest: (2 elements)
                - requestId: "req-123"
                - decision: PermissionDecision.allow

            """
        }
        assertInlineSnapshot(
            of: AppAction.resolveRequest(requestId: "req-456", decision: .deny), as: .dump
        ) {
            """
            ▿ AppAction
              ▿ resolveRequest: (2 elements)
                - requestId: "req-456"
                - decision: PermissionDecision.deny

            """
        }
        assertInlineSnapshot(of: AppAction.ntfyConfigChanged, as: .dump) {
            """
            - AppAction.ntfyConfigChanged

            """
        }
        assertInlineSnapshot(of: AppAction.timeoutConfigChanged, as: .dump) {
            """
            - AppAction.timeoutConfigChanged

            """
        }
        assertInlineSnapshot(of: AppAction.stop, as: .dump) {
            """
            - AppAction.stop

            """
        }
    }
}

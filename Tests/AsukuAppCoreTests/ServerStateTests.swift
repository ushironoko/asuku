import Foundation
import InlineSnapshotTesting
import Testing

@testable import AsukuAppCore

@Suite("ServerState Tests")
struct ServerStateTests {

    // MARK: - State properties

    @Test("stopped state: not running, no error")
    func stoppedState() {
        let state = ServerState.stopped
        #expect(state.isRunning == false)
        #expect(state.errorMessage == nil)
    }

    @Test("running state: is running, no error")
    func runningState() {
        let state = ServerState.running
        #expect(state.isRunning == true)
        #expect(state.errorMessage == nil)
    }

    @Test("failed state: not running, has error message")
    func failedState() {
        let state = ServerState.failed("Connection refused")
        #expect(state.isRunning == false)
        #expect(state.errorMessage == "Connection refused")
    }

    @Test("failed state with empty error message")
    func failedEmptyMessage() {
        let state = ServerState.failed("")
        #expect(state.isRunning == false)
        #expect(state.errorMessage == "")
    }

    // MARK: - Equatable

    @Test("same states are equal")
    func equalStates() {
        #expect(ServerState.stopped == ServerState.stopped)
        #expect(ServerState.running == ServerState.running)
        #expect(ServerState.failed("err") == ServerState.failed("err"))
    }

    @Test("different states are not equal")
    func differentStates() {
        #expect(ServerState.stopped != ServerState.running)
        #expect(ServerState.running != ServerState.failed("err"))
        #expect(ServerState.failed("a") != ServerState.failed("b"))
    }

    // MARK: - Snapshot

    @Test("snapshot of all states")
    func snapshotAllStates() {
        assertInlineSnapshot(of: String(describing: ServerState.stopped), as: .lines) {
            """
            stopped
            """
        }
        assertInlineSnapshot(of: String(describing: ServerState.running), as: .lines) {
            """
            running
            """
        }
        assertInlineSnapshot(of: String(describing: ServerState.failed("port in use")), as: .lines) {
            """
            failed("port in use")
            """
        }
    }
}

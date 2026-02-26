import Foundation
import Testing

@testable import AsukuAppCore
@testable import AsukuShared

/// Mock responder that records sent responses for test verification
final class MockIPCResponder: IPCResponding, @unchecked Sendable {
    private let lock = NSLock()
    private var _responses: [IPCResponse] = []

    var responses: [IPCResponse] {
        lock.withLock { _responses }
    }

    func send(_ response: IPCResponse) {
        lock.withLock { _responses.append(response) }
    }
}

/// Helper to create test events
private func makeEvent(requestId: String = UUID().uuidString) -> PermissionRequestEvent {
    PermissionRequestEvent(
        requestId: requestId,
        sessionId: "test-session",
        toolName: "Bash",
        toolInput: ["command": .string("echo test")],
        cwd: "/tmp"
    )
}

@Suite("PendingRequestManager Tests")
struct PendingRequestManagerTests {

    // MARK: - rescheduleTimeouts: disable (nil)

    @Test("rescheduleTimeouts with nil cancels all timeout tasks")
    func rescheduleDisable() async {
        let manager = PendingRequestManager()
        let responder = MockIPCResponder()

        // Add a request with a very short timeout
        let event = makeEvent()
        await manager.addRequest(event: event, responder: responder, timeoutSeconds: 1.0)

        // Disable timeouts
        await manager.rescheduleTimeouts(effectiveTimeout: nil)

        // Wait longer than the original timeout
        try? await Task.sleep(for: .seconds(1.5))

        // Request should still be pending (not auto-denied)
        let count = await manager.pendingCount
        #expect(count == 1, "Request should remain pending when timeouts are disabled")
        #expect(responder.responses.isEmpty, "No response should have been sent")
    }

    // MARK: - rescheduleTimeouts: enable (non-nil)

    @Test("rescheduleTimeouts with value re-enables timeout for pending requests")
    func rescheduleEnable() async {
        let manager = PendingRequestManager()
        let responder = MockIPCResponder()

        let timedOut = expectation(description: "timeout fired")
        await manager.setOnTimeout { _ in
            timedOut.fulfill()
        }

        // Add request with no timeout
        let event = makeEvent()
        await manager.addRequest(event: event, responder: responder, timeoutSeconds: nil)

        // Enable timeouts with a short value
        await manager.rescheduleTimeouts(effectiveTimeout: 0.5)

        // Wait for the timeout to fire
        await fulfillment(of: [timedOut], timeout: 3.0)

        // Request should have been auto-denied
        let count = await manager.pendingCount
        #expect(count == 0, "Request should have been auto-denied")
        #expect(responder.responses.count == 1)
        #expect(responder.responses.first?.decision == .deny)
    }

    // MARK: - rescheduleTimeouts: lower below elapsed

    @Test("rescheduleTimeouts with timeout below elapsed time triggers immediate deny")
    func rescheduleLowerBelowElapsed() async {
        let manager = PendingRequestManager()
        let responder = MockIPCResponder()

        let timedOut = expectation(description: "timeout fired")
        await manager.setOnTimeout { _ in
            timedOut.fulfill()
        }

        // Add request with a long timeout
        let event = makeEvent()
        await manager.addRequest(event: event, responder: responder, timeoutSeconds: 300)

        // Wait a bit so elapsed > 0
        try? await Task.sleep(for: .seconds(0.3))

        // Reschedule with a very short timeout (less than elapsed time)
        await manager.rescheduleTimeouts(effectiveTimeout: 0.1)

        // Should fire almost immediately since elapsed > effectiveTimeout
        await fulfillment(of: [timedOut], timeout: 3.0)

        let count = await manager.pendingCount
        #expect(count == 0, "Request should have been auto-denied immediately")
        #expect(responder.responses.first?.decision == .deny)
    }
}

// MARK: - Helpers (XCTest-like expectations for Swift Testing)

private func expectation(description: String) -> TestExpectation {
    TestExpectation(description: description)
}

private func fulfillment(of expectations: [TestExpectation], timeout: TimeInterval) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if expectations.allSatisfy({ $0.isFulfilled }) {
            return
        }
        try? await Task.sleep(for: .milliseconds(50))
    }
    for exp in expectations where !exp.isFulfilled {
        Issue.record("Expectation '\(exp.description)' was not fulfilled within \(timeout)s")
    }
}

private final class TestExpectation: @unchecked Sendable {
    let description: String
    private var _isFulfilled = false
    private let lock = NSLock()

    var isFulfilled: Bool {
        lock.withLock { _isFulfilled }
    }

    init(description: String) {
        self.description = description
    }

    func fulfill() {
        lock.withLock { _isFulfilled = true }
    }
}

extension PendingRequestManager {
    func setOnTimeout(_ handler: @escaping @Sendable (String) -> Void) {
        onTimeout = handler
    }
}

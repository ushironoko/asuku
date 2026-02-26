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

    // MARK: - addRequest & basic queries

    @Test("addRequest stores request and increments count")
    func addRequestBasic() async {
        let manager = PendingRequestManager()
        let responder = MockIPCResponder()
        let event = makeEvent(requestId: "r1")

        await manager.addRequest(event: event, responder: responder)

        let count = await manager.pendingCount
        #expect(count == 1)
        let request = await manager.getRequest("r1")
        #expect(request != nil)
        #expect(request?.id == "r1")
    }

    @Test("addRequest with nil timeout does not auto-deny")
    func addRequestNilTimeout() async {
        let manager = PendingRequestManager()
        let responder = MockIPCResponder()
        let event = makeEvent(requestId: "r1")

        await manager.addRequest(event: event, responder: responder, timeoutSeconds: nil)
        try? await Task.sleep(for: .seconds(0.3))

        let count = await manager.pendingCount
        #expect(count == 1)
        #expect(responder.responses.isEmpty)
    }

    @Test("pendingRequests returns sorted by createdAt")
    func pendingRequestsSorted() async {
        let manager = PendingRequestManager()
        let responder = MockIPCResponder()

        let e1 = makeEvent(requestId: "r1")
        await manager.addRequest(event: e1, responder: responder, timeoutSeconds: nil)
        try? await Task.sleep(for: .milliseconds(10))
        let e2 = makeEvent(requestId: "r2")
        await manager.addRequest(event: e2, responder: responder, timeoutSeconds: nil)

        let pending = await manager.pendingRequests
        #expect(pending.count == 2)
        #expect(pending[0].id == "r1")
        #expect(pending[1].id == "r2")
    }

    @Test("getRequest returns nil for unknown ID")
    func getRequestUnknown() async {
        let manager = PendingRequestManager()
        let result = await manager.getRequest("nonexistent")
        #expect(result == nil)
    }

    // MARK: - resolve

    @Test("resolve sends response and removes request")
    func resolveSuccess() async {
        let manager = PendingRequestManager()
        let responder = MockIPCResponder()
        let event = makeEvent(requestId: "r1")
        await manager.addRequest(event: event, responder: responder, timeoutSeconds: nil)

        let resolved = await manager.resolve(requestId: "r1", decision: .allow)
        #expect(resolved == true)
        #expect(responder.responses.count == 1)
        #expect(responder.responses.first?.decision == .allow)

        let count = await manager.pendingCount
        #expect(count == 0)
    }

    @Test("resolve returns false for unknown request")
    func resolveUnknown() async {
        let manager = PendingRequestManager()
        let resolved = await manager.resolve(requestId: "nonexistent", decision: .allow)
        #expect(resolved == false)
    }

    // MARK: - remove

    @Test("remove deletes request without sending response")
    func removeRequest() async {
        let manager = PendingRequestManager()
        let responder = MockIPCResponder()
        let event = makeEvent(requestId: "r1")
        await manager.addRequest(event: event, responder: responder, timeoutSeconds: nil)

        await manager.remove(requestId: "r1")

        let count = await manager.pendingCount
        #expect(count == 0)
        #expect(responder.responses.isEmpty)
    }

    // MARK: - PendingRequest properties

    @Test("isExpired returns false when timeoutSeconds is nil")
    func isExpiredNilTimeout() {
        let request = PendingRequest(
            id: "r1",
            event: makeEvent(),
            responder: MockIPCResponder(),
            createdAt: Date.distantPast,
            timeoutSeconds: nil
        )
        #expect(request.isExpired == false)
    }

    @Test("isExpired returns true when elapsed exceeds timeout")
    func isExpiredTrue() {
        let request = PendingRequest(
            id: "r1",
            event: makeEvent(),
            responder: MockIPCResponder(),
            createdAt: Date.distantPast,
            timeoutSeconds: 10
        )
        #expect(request.isExpired == true)
    }

    @Test("isExpired returns false when within timeout")
    func isExpiredFalse() {
        let request = PendingRequest(
            id: "r1",
            event: makeEvent(),
            responder: MockIPCResponder(),
            createdAt: Date(),
            timeoutSeconds: 9999
        )
        #expect(request.isExpired == false)
    }

    // MARK: - displayTitle

    @Test("displayTitle for Bash with command")
    func displayTitleBash() {
        let event = PermissionRequestEvent(
            requestId: "r1", sessionId: "s1", toolName: "Bash",
            toolInput: ["command": .string("ls -la")], cwd: "/tmp"
        )
        let request = PendingRequest(
            id: "r1", event: event, responder: MockIPCResponder(),
            createdAt: Date(), timeoutSeconds: nil
        )
        #expect(request.displayTitle.hasPrefix("Bash: "))
    }

    @Test("displayTitle for Bash without command")
    func displayTitleBashNoCommand() {
        let event = PermissionRequestEvent(
            requestId: "r1", sessionId: "s1", toolName: "Bash",
            toolInput: [:], cwd: "/tmp"
        )
        let request = PendingRequest(
            id: "r1", event: event, responder: MockIPCResponder(),
            createdAt: Date(), timeoutSeconds: nil
        )
        #expect(request.displayTitle == "Bash command")
    }

    @Test("displayTitle for Write with file_path")
    func displayTitleWrite() {
        let event = PermissionRequestEvent(
            requestId: "r1", sessionId: "s1", toolName: "Write",
            toolInput: ["file_path": .string("/tmp/test.txt")], cwd: "/tmp"
        )
        let request = PendingRequest(
            id: "r1", event: event, responder: MockIPCResponder(),
            createdAt: Date(), timeoutSeconds: nil
        )
        #expect(request.displayTitle == "Write: /tmp/test.txt")
    }

    @Test("displayTitle for Edit without file_path")
    func displayTitleEditNoPath() {
        let event = PermissionRequestEvent(
            requestId: "r1", sessionId: "s1", toolName: "Edit",
            toolInput: [:], cwd: "/tmp"
        )
        let request = PendingRequest(
            id: "r1", event: event, responder: MockIPCResponder(),
            createdAt: Date(), timeoutSeconds: nil
        )
        #expect(request.displayTitle == "Edit")
    }

    @Test("displayTitle for unknown tool")
    func displayTitleUnknown() {
        let event = PermissionRequestEvent(
            requestId: "r1", sessionId: "s1", toolName: "CustomTool",
            toolInput: [:], cwd: "/tmp"
        )
        let request = PendingRequest(
            id: "r1", event: event, responder: MockIPCResponder(),
            createdAt: Date(), timeoutSeconds: nil
        )
        #expect(request.displayTitle == "CustomTool")
    }

    // MARK: - notificationBody

    @Test("notificationBody for Bash with command")
    func notificationBodyBash() {
        let event = PermissionRequestEvent(
            requestId: "r1", sessionId: "s1", toolName: "Bash",
            toolInput: ["command": .string("echo hello")], cwd: "/tmp"
        )
        let request = PendingRequest(
            id: "r1", event: event, responder: MockIPCResponder(),
            createdAt: Date(), timeoutSeconds: nil
        )
        #expect(request.notificationBody.contains("echo hello"))
    }

    @Test("notificationBody for Bash without command")
    func notificationBodyBashNoCommand() {
        let event = PermissionRequestEvent(
            requestId: "r1", sessionId: "s1", toolName: "Bash",
            toolInput: [:], cwd: "/tmp"
        )
        let request = PendingRequest(
            id: "r1", event: event, responder: MockIPCResponder(),
            createdAt: Date(), timeoutSeconds: nil
        )
        #expect(request.notificationBody == "Execute bash command")
    }

    @Test("notificationBody for Write with file_path")
    func notificationBodyWrite() {
        let event = PermissionRequestEvent(
            requestId: "r1", sessionId: "s1", toolName: "Write",
            toolInput: ["file_path": .string("/tmp/out.txt")], cwd: "/tmp"
        )
        let request = PendingRequest(
            id: "r1", event: event, responder: MockIPCResponder(),
            createdAt: Date(), timeoutSeconds: nil
        )
        #expect(request.notificationBody == "Write to /tmp/out.txt")
    }

    @Test("notificationBody for Write without file_path")
    func notificationBodyWriteNoPath() {
        let event = PermissionRequestEvent(
            requestId: "r1", sessionId: "s1", toolName: "Write",
            toolInput: [:], cwd: "/tmp"
        )
        let request = PendingRequest(
            id: "r1", event: event, responder: MockIPCResponder(),
            createdAt: Date(), timeoutSeconds: nil
        )
        #expect(request.notificationBody == "Write file")
    }

    @Test("notificationBody for Edit with file_path")
    func notificationBodyEdit() {
        let event = PermissionRequestEvent(
            requestId: "r1", sessionId: "s1", toolName: "Edit",
            toolInput: ["file_path": .string("/tmp/file.swift")], cwd: "/tmp"
        )
        let request = PendingRequest(
            id: "r1", event: event, responder: MockIPCResponder(),
            createdAt: Date(), timeoutSeconds: nil
        )
        #expect(request.notificationBody == "Edit /tmp/file.swift")
    }

    @Test("notificationBody for Edit without file_path")
    func notificationBodyEditNoPath() {
        let event = PermissionRequestEvent(
            requestId: "r1", sessionId: "s1", toolName: "Edit",
            toolInput: [:], cwd: "/tmp"
        )
        let request = PendingRequest(
            id: "r1", event: event, responder: MockIPCResponder(),
            createdAt: Date(), timeoutSeconds: nil
        )
        #expect(request.notificationBody == "Edit file")
    }

    @Test("notificationBody for unknown tool")
    func notificationBodyUnknown() {
        let event = PermissionRequestEvent(
            requestId: "r1", sessionId: "s1", toolName: "Custom",
            toolInput: ["key": .string("val")], cwd: "/tmp"
        )
        let request = PendingRequest(
            id: "r1", event: event, responder: MockIPCResponder(),
            createdAt: Date(), timeoutSeconds: nil
        )
        #expect(request.notificationBody.contains("Custom"))
    }

    // MARK: - rescheduleTimeouts updates timeoutSeconds

    @Test("rescheduleTimeouts updates stored timeoutSeconds on requests")
    func rescheduleUpdatesTimeoutSeconds() async {
        let manager = PendingRequestManager()
        let responder = MockIPCResponder()
        let event = makeEvent(requestId: "r1")

        await manager.addRequest(event: event, responder: responder, timeoutSeconds: 280)

        let before = await manager.getRequest("r1")
        #expect(before?.timeoutSeconds == 280)

        await manager.rescheduleTimeouts(effectiveTimeout: 60)

        let after = await manager.getRequest("r1")
        #expect(after?.timeoutSeconds == 60)
    }

    @Test("rescheduleTimeouts with nil sets timeoutSeconds to nil")
    func rescheduleNilUpdatesTimeoutSeconds() async {
        let manager = PendingRequestManager()
        let responder = MockIPCResponder()
        let event = makeEvent(requestId: "r1")

        await manager.addRequest(event: event, responder: responder, timeoutSeconds: 280)
        await manager.rescheduleTimeouts(effectiveTimeout: nil)

        let request = await manager.getRequest("r1")
        #expect(request?.timeoutSeconds == nil)
        #expect(request?.isExpired == false)
    }

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

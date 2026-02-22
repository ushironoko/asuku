import AsukuShared
import Foundation
import InlineSnapshotTesting
import Testing

@testable import AsukuAppCore

@Suite("RecentEvent Tests")
struct RecentEventTests {

    // MARK: - Kind enum

    @Test("Kind.notification is equatable")
    func kindNotification() {
        #expect(RecentEvent.Kind.notification == RecentEvent.Kind.notification)
    }

    @Test("Kind.timeout is equatable")
    func kindTimeout() {
        #expect(RecentEvent.Kind.timeout == RecentEvent.Kind.timeout)
    }

    @Test("Kind.permissionResponse equality with same decision")
    func kindPermissionResponseEqual() {
        #expect(
            RecentEvent.Kind.permissionResponse(.allow)
                == RecentEvent.Kind.permissionResponse(.allow))
        #expect(
            RecentEvent.Kind.permissionResponse(.deny)
                == RecentEvent.Kind.permissionResponse(.deny))
    }

    @Test("Kind.permissionResponse inequality with different decisions")
    func kindPermissionResponseNotEqual() {
        #expect(
            RecentEvent.Kind.permissionResponse(.allow)
                != RecentEvent.Kind.permissionResponse(.deny))
    }

    @Test("Different Kind cases are not equal")
    func kindDifferentCases() {
        #expect(RecentEvent.Kind.notification != RecentEvent.Kind.timeout)
        #expect(RecentEvent.Kind.notification != RecentEvent.Kind.permissionResponse(.allow))
        #expect(RecentEvent.Kind.timeout != RecentEvent.Kind.permissionResponse(.deny))
    }

    // MARK: - displayText

    @Test("displayText for notification shows tool name only")
    func displayTextNotification() {
        let event = makeEvent(toolName: "Build Complete", kind: .notification)
        #expect(event.displayText == "Build Complete")
    }

    @Test("displayText for allow shows Allowed")
    func displayTextAllow() {
        let event = makeEvent(toolName: "Bash", kind: .permissionResponse(.allow))
        #expect(event.displayText == "Bash — Allowed")
    }

    @Test("displayText for deny shows Denied")
    func displayTextDeny() {
        let event = makeEvent(toolName: "Write", kind: .permissionResponse(.deny))
        #expect(event.displayText == "Write — Denied")
    }

    @Test("displayText for timeout shows Timed Out")
    func displayTextTimeout() {
        let event = makeEvent(toolName: "Edit", kind: .timeout)
        #expect(event.displayText == "Edit — Timed Out")
    }

    // MARK: - timeText

    @Test("timeText produces non-empty relative time string")
    func timeTextNonEmpty() {
        let event = makeEvent(
            toolName: "Bash",
            kind: .notification,
            timestamp: Date().addingTimeInterval(-60)
        )
        #expect(!event.timeText.isEmpty)
    }

    // MARK: - Identifiable

    @Test("events with different IDs are distinguishable")
    func identifiable() {
        let a = makeEvent(toolName: "A", kind: .notification, id: "id-1")
        let b = makeEvent(toolName: "B", kind: .notification, id: "id-2")
        #expect(a.id != b.id)
    }

    // MARK: - Snapshot: displayText for all kinds

    @Test("snapshot displayText for all event kinds")
    func snapshotDisplayText() {
        let kinds: [(String, RecentEvent.Kind)] = [
            ("notification", .notification),
            ("allow", .permissionResponse(.allow)),
            ("deny", .permissionResponse(.deny)),
            ("timeout", .timeout),
        ]
        let texts = kinds.map { (label, kind) in
            let event = makeEvent(toolName: "Bash", kind: kind)
            return "\(label): \(event.displayText)"
        }.joined(separator: "\n")

        assertInlineSnapshot(of: texts, as: .lines) {
            """
            notification: Bash
            allow: Bash — Allowed
            deny: Bash — Denied
            timeout: Bash — Timed Out
            """
        }
    }

    @Test("snapshot dump of a recent event")
    func snapshotDump() {
        let event = RecentEvent(
            id: "test-id",
            toolName: "Bash",
            kind: .permissionResponse(.allow),
            timestamp: Date(timeIntervalSince1970: 1700000000),
            sessionId: "session-1"
        )
        assertInlineSnapshot(of: event, as: .dump) {
            """
            ▿ RecentEvent
              - id: "test-id"
              ▿ kind: Kind
                - permissionResponse: PermissionDecision.allow
              - sessionId: "session-1"
              - timestamp: 2023-11-14T22:13:20Z
              - toolName: "Bash"

            """
        }
    }

    // MARK: - Helpers

    private func makeEvent(
        toolName: String,
        kind: RecentEvent.Kind,
        timestamp: Date = Date(),
        id: String = UUID().uuidString
    ) -> RecentEvent {
        RecentEvent(
            id: id,
            toolName: toolName,
            kind: kind,
            timestamp: timestamp,
            sessionId: "test-session"
        )
    }
}

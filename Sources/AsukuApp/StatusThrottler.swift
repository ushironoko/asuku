import AsukuShared
import Foundation

/// Throttles incoming status updates, batching them on a 1-second interval.
/// Also handles stale session removal (10 minute timeout).
actor StatusThrottler {
    private var latestEvents: [String: StatusUpdateEvent] = [:]
    private var flushTask: Task<Void, Never>?
    private let staleTimeout: TimeInterval = 600  // 10 minutes
    private var hasChanges = false
    private var onFlush:
        (@MainActor @Sendable (_ active: [StatusUpdateEvent], _ staleSessionIds: [String]) -> Void)?

    func setOnFlush(
        _ handler: @escaping @MainActor @Sendable (
            _ active: [StatusUpdateEvent], _ staleSessionIds: [String]
        ) -> Void
    ) {
        onFlush = handler
        startPeriodicFlush()
    }

    func receive(_ event: StatusUpdateEvent) {
        latestEvents[event.sessionId] = event
        hasChanges = true
    }

    private func startPeriodicFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { break }
                await self.flush()
            }
        }
    }

    private func flush() {
        guard let onFlush else { return }

        // Remove stale sessions first, tracking which were evicted
        let cutoff = Date().addingTimeInterval(-staleTimeout)
        let previousIds = Set(latestEvents.keys)
        latestEvents = latestEvents.filter { $0.value.timestamp > cutoff }
        let currentIds = Set(latestEvents.keys)
        let staleSessionIds = Array(previousIds.subtracting(currentIds))

        // Only flush if there are actual changes or stale evictions
        guard hasChanges || !staleSessionIds.isEmpty else { return }

        let events = Array(latestEvents.values)
        hasChanges = false

        Task { @MainActor in
            onFlush(events, staleSessionIds)
        }
    }

    func stop() {
        flushTask?.cancel()
        flushTask = nil
    }
}

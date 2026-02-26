import AsukuShared
import Foundation

enum StatuslineHandler {
    /// Handles statusline subcommand. Non-throwing — all errors are caught internally.
    /// Always writes inputData to stdout (passthrough guarantee).
    static func handle(inputData: Data) {
        // Passthrough guarantee: always write input to stdout
        defer {
            FileHandle.standardOutput.write(inputData)
        }

        // Parse JSON (failure = passthrough only)
        let decoder = JSONDecoder()
        guard let statusline = try? decoder.decode(StatuslineData.self, from: inputData) else {
            return
        }

        // Resolve sessionId: fallback to transcriptPath, discard if both missing
        guard let sessionId = statusline.sessionId ?? statusline.transcriptPath else {
            return
        }

        // Build IPC message
        let event = StatusUpdateEvent(
            sessionId: sessionId,
            statusline: statusline,
            timestamp: Date()
        )
        let message = IPCMessage(payload: .statusUpdate(event))

        // Fire-and-forget IPC (silently ignore if app is not running)
        try? IPCClient.sendOnly(message)
    }
}

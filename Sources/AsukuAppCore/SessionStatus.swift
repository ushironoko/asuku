import AsukuShared
import Foundation

// MARK: - Session Status

public struct SessionStatus: Sendable, Equatable, Identifiable {
    public var id: String { sessionId }
    public let sessionId: String
    public var statusline: StatuslineData
    public var lastUpdated: Date

    public var modelName: String? { statusline.model?.displayName ?? statusline.model?.id }
    public var contextUsedPercent: Int? { statusline.contextWindow?.usedPercentage }
    public var totalCost: Double? { statusline.cost?.totalCostUsd }
    public var projectDir: String? { statusline.workspace?.projectDir ?? statusline.cwd }
    public var agentName: String? { statusline.agent?.name }

    /// Whether `sessionId` looks like a real Claude session ID (not a transcript path fallback).
    public var hasValidSessionId: Bool {
        !sessionId.isEmpty && !sessionId.contains("/")
    }

    public var remoteControlURL: URL? {
        guard hasValidSessionId else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "claude.ai"
        components.path = "/code/session_\(sessionId)"
        return components.url
    }

    public init(sessionId: String, statusline: StatuslineData, lastUpdated: Date) {
        self.sessionId = sessionId
        self.statusline = statusline
        self.lastUpdated = lastUpdated
    }
}

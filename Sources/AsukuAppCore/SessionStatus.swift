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

    public init(sessionId: String, statusline: StatuslineData, lastUpdated: Date) {
        self.sessionId = sessionId
        self.statusline = statusline
        self.lastUpdated = lastUpdated
    }
}

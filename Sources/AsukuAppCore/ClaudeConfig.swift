import Foundation

// MARK: - Plugin Information

public struct EnabledPlugin: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let marketplace: String
    public let isEnabled: Bool
    public let version: String

    public init(id: String, name: String, marketplace: String, isEnabled: Bool, version: String) {
        self.id = id
        self.name = name
        self.marketplace = marketplace
        self.isEnabled = isEnabled
        self.version = version
    }
}

// MARK: - Session History

public struct SessionHistoryEntry: Sendable, Equatable, Identifiable {
    public let id: String
    public let sessionId: String
    public let projectPath: String
    public let timestamp: Date
    public let displayText: String

    public init(
        id: String, sessionId: String, projectPath: String, timestamp: Date, displayText: String
    ) {
        self.id = id
        self.sessionId = sessionId
        self.projectPath = projectPath
        self.timestamp = timestamp
        self.displayText = displayText
    }
}

import Foundation

// MARK: - Statusline JSON Data Model

/// Represents the full statusline JSON that Claude Code sends via stdin.
/// All fields are Optional since the JSON may be partial.
public struct StatuslineData: Codable, Sendable, Equatable {
    public let cwd: String?
    public let sessionId: String?
    public let transcriptPath: String?
    public let model: ModelInfo?
    public let workspace: WorkspaceInfo?
    public let version: String?
    public let cost: CostInfo?
    public let contextWindow: ContextWindowInfo?
    public let exceedsContextLimit: Bool?
    public let agent: AgentInfo?

    private enum CodingKeys: String, CodingKey {
        case cwd
        case sessionId = "session_id"
        case transcriptPath = "transcript_path"
        case model, workspace, version, cost
        case contextWindow = "context_window"
        case exceedsContextLimit = "exceeds_200k_tokens"
        case agent
    }

    public init(
        cwd: String? = nil,
        sessionId: String? = nil,
        transcriptPath: String? = nil,
        model: ModelInfo? = nil,
        workspace: WorkspaceInfo? = nil,
        version: String? = nil,
        cost: CostInfo? = nil,
        contextWindow: ContextWindowInfo? = nil,
        exceedsContextLimit: Bool? = nil,
        agent: AgentInfo? = nil
    ) {
        self.cwd = cwd
        self.sessionId = sessionId
        self.transcriptPath = transcriptPath
        self.model = model
        self.workspace = workspace
        self.version = version
        self.cost = cost
        self.contextWindow = contextWindow
        self.exceedsContextLimit = exceedsContextLimit
        self.agent = agent
    }
}

public struct ModelInfo: Codable, Sendable, Equatable {
    public let id: String
    public let displayName: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }

    public init(id: String, displayName: String? = nil) {
        self.id = id
        self.displayName = displayName
    }
}

public struct WorkspaceInfo: Codable, Sendable, Equatable {
    public let currentDir: String?
    public let projectDir: String?

    private enum CodingKeys: String, CodingKey {
        case currentDir = "current_dir"
        case projectDir = "project_dir"
    }

    public init(currentDir: String? = nil, projectDir: String? = nil) {
        self.currentDir = currentDir
        self.projectDir = projectDir
    }
}

public struct CostInfo: Codable, Sendable, Equatable {
    public let totalCostUsd: Double?
    public let totalDurationMs: Int?
    public let totalApiDurationMs: Int?
    public let totalLinesAdded: Int?
    public let totalLinesRemoved: Int?

    private enum CodingKeys: String, CodingKey {
        case totalCostUsd = "total_cost_usd"
        case totalDurationMs = "total_duration_ms"
        case totalApiDurationMs = "total_api_duration_ms"
        case totalLinesAdded = "total_lines_added"
        case totalLinesRemoved = "total_lines_removed"
    }

    public init(
        totalCostUsd: Double? = nil,
        totalDurationMs: Int? = nil,
        totalApiDurationMs: Int? = nil,
        totalLinesAdded: Int? = nil,
        totalLinesRemoved: Int? = nil
    ) {
        self.totalCostUsd = totalCostUsd
        self.totalDurationMs = totalDurationMs
        self.totalApiDurationMs = totalApiDurationMs
        self.totalLinesAdded = totalLinesAdded
        self.totalLinesRemoved = totalLinesRemoved
    }
}

public struct ContextWindowInfo: Codable, Sendable, Equatable {
    public let totalInputTokens: Int?
    public let totalOutputTokens: Int?
    public let contextWindowSize: Int?
    public let usedPercentage: Int?
    public let remainingPercentage: Int?
    public let currentUsage: TokenUsage?

    private enum CodingKeys: String, CodingKey {
        case totalInputTokens = "total_input_tokens"
        case totalOutputTokens = "total_output_tokens"
        case contextWindowSize = "context_window_size"
        case usedPercentage = "used_percentage"
        case remainingPercentage = "remaining_percentage"
        case currentUsage = "current_usage"
    }

    public init(
        totalInputTokens: Int? = nil,
        totalOutputTokens: Int? = nil,
        contextWindowSize: Int? = nil,
        usedPercentage: Int? = nil,
        remainingPercentage: Int? = nil,
        currentUsage: TokenUsage? = nil
    ) {
        self.totalInputTokens = totalInputTokens
        self.totalOutputTokens = totalOutputTokens
        self.contextWindowSize = contextWindowSize
        self.usedPercentage = usedPercentage
        self.remainingPercentage = remainingPercentage
        self.currentUsage = currentUsage
    }
}

public struct TokenUsage: Codable, Sendable, Equatable {
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let cacheCreationInputTokens: Int?
    public let cacheReadInputTokens: Int?

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
    }

    public init(
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        cacheCreationInputTokens: Int? = nil,
        cacheReadInputTokens: Int? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
    }
}

public struct AgentInfo: Codable, Sendable, Equatable {
    public let name: String?

    public init(name: String? = nil) {
        self.name = name
    }
}

// MARK: - Status Update Event

public struct StatusUpdateEvent: Codable, Sendable {
    public let sessionId: String
    public let statusline: StatuslineData
    public let timestamp: Date

    public init(sessionId: String, statusline: StatuslineData, timestamp: Date = Date()) {
        self.sessionId = sessionId
        self.statusline = statusline
        self.timestamp = timestamp
    }
}

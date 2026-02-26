import Foundation
import InlineSnapshotTesting
import Testing

@testable import AsukuAppCore
@testable import AsukuShared

@Suite("SessionStatus Tests")
struct SessionStatusTests {

    // MARK: - Computed Properties

    @Test("modelName returns displayName when available")
    func modelNameDisplayName() {
        let statusline = StatuslineData(
            model: ModelInfo(id: "claude-opus-4-6", displayName: "Opus 4.6")
        )
        let session = SessionStatus(
            sessionId: "s1", statusline: statusline, lastUpdated: Date())

        #expect(session.modelName == "Opus 4.6")
    }

    @Test("modelName falls back to id when displayName is nil")
    func modelNameFallbackToId() {
        let statusline = StatuslineData(
            model: ModelInfo(id: "claude-opus-4-6")
        )
        let session = SessionStatus(
            sessionId: "s1", statusline: statusline, lastUpdated: Date())

        #expect(session.modelName == "claude-opus-4-6")
    }

    @Test("modelName returns nil when model is nil")
    func modelNameNil() {
        let statusline = StatuslineData()
        let session = SessionStatus(
            sessionId: "s1", statusline: statusline, lastUpdated: Date())

        #expect(session.modelName == nil)
    }

    @Test("contextUsedPercent returns value when available")
    func contextUsedPercent() {
        let statusline = StatuslineData(
            contextWindow: ContextWindowInfo(usedPercentage: 78)
        )
        let session = SessionStatus(
            sessionId: "s1", statusline: statusline, lastUpdated: Date())

        #expect(session.contextUsedPercent == 78)
    }

    @Test("contextUsedPercent returns nil when contextWindow is nil")
    func contextUsedPercentNil() {
        let statusline = StatuslineData()
        let session = SessionStatus(
            sessionId: "s1", statusline: statusline, lastUpdated: Date())

        #expect(session.contextUsedPercent == nil)
    }

    @Test("totalCost returns value when available")
    func totalCost() {
        let statusline = StatuslineData(
            cost: CostInfo(totalCostUsd: 0.0123)
        )
        let session = SessionStatus(
            sessionId: "s1", statusline: statusline, lastUpdated: Date())

        #expect(session.totalCost == 0.0123)
    }

    @Test("totalCost returns nil when cost is nil")
    func totalCostNil() {
        let statusline = StatuslineData()
        let session = SessionStatus(
            sessionId: "s1", statusline: statusline, lastUpdated: Date())

        #expect(session.totalCost == nil)
    }

    @Test("projectDir returns workspace.projectDir when available")
    func projectDirFromWorkspace() {
        let statusline = StatuslineData(
            cwd: "/fallback",
            workspace: WorkspaceInfo(projectDir: "/project")
        )
        let session = SessionStatus(
            sessionId: "s1", statusline: statusline, lastUpdated: Date())

        #expect(session.projectDir == "/project")
    }

    @Test("projectDir falls back to cwd when workspace.projectDir is nil")
    func projectDirFallbackToCwd() {
        let statusline = StatuslineData(cwd: "/fallback")
        let session = SessionStatus(
            sessionId: "s1", statusline: statusline, lastUpdated: Date())

        #expect(session.projectDir == "/fallback")
    }

    @Test("projectDir returns nil when both workspace.projectDir and cwd are nil")
    func projectDirNil() {
        let statusline = StatuslineData()
        let session = SessionStatus(
            sessionId: "s1", statusline: statusline, lastUpdated: Date())

        #expect(session.projectDir == nil)
    }

    @Test("agentName returns value when available")
    func agentName() {
        let statusline = StatuslineData(agent: AgentInfo(name: "task-agent"))
        let session = SessionStatus(
            sessionId: "s1", statusline: statusline, lastUpdated: Date())

        #expect(session.agentName == "task-agent")
    }

    @Test("agentName returns nil when agent is nil")
    func agentNameNil() {
        let statusline = StatuslineData()
        let session = SessionStatus(
            sessionId: "s1", statusline: statusline, lastUpdated: Date())

        #expect(session.agentName == nil)
    }

    @Test("id is computed from sessionId")
    func idIsSessionId() {
        let statusline = StatuslineData()
        let session = SessionStatus(
            sessionId: "my-session", statusline: statusline, lastUpdated: Date())

        #expect(session.id == "my-session")
    }

    // MARK: - Equatable

    @Test("SessionStatus with identical values are equal")
    func equatable() {
        let statusline = StatuslineData(
            model: ModelInfo(id: "opus", displayName: "Opus 4.6")
        )
        let date = Date(timeIntervalSince1970: 1700000000)
        let a = SessionStatus(sessionId: "s1", statusline: statusline, lastUpdated: date)
        let b = SessionStatus(sessionId: "s1", statusline: statusline, lastUpdated: date)
        #expect(a == b)
    }

    @Test("SessionStatus with different sessionIds are not equal")
    func notEqualDifferentSession() {
        let statusline = StatuslineData()
        let date = Date()
        let a = SessionStatus(sessionId: "s1", statusline: statusline, lastUpdated: date)
        let b = SessionStatus(sessionId: "s2", statusline: statusline, lastUpdated: date)
        #expect(a != b)
    }

    @Test("SessionStatus with different statuslines are not equal")
    func notEqualDifferentStatusline() {
        let date = Date()
        let a = SessionStatus(
            sessionId: "s1",
            statusline: StatuslineData(model: ModelInfo(id: "opus")),
            lastUpdated: date)
        let b = SessionStatus(
            sessionId: "s1",
            statusline: StatuslineData(model: ModelInfo(id: "sonnet")),
            lastUpdated: date)
        #expect(a != b)
    }

    // MARK: - Boundary Values

    @Test("contextUsedPercent at 0%")
    func contextZeroPercent() {
        let statusline = StatuslineData(
            contextWindow: ContextWindowInfo(usedPercentage: 0)
        )
        let session = SessionStatus(
            sessionId: "s1", statusline: statusline, lastUpdated: Date())
        #expect(session.contextUsedPercent == 0)
    }

    @Test("contextUsedPercent at 100%")
    func contextFullPercent() {
        let statusline = StatuslineData(
            contextWindow: ContextWindowInfo(usedPercentage: 100)
        )
        let session = SessionStatus(
            sessionId: "s1", statusline: statusline, lastUpdated: Date())
        #expect(session.contextUsedPercent == 100)
    }

    @Test("totalCost at zero")
    func totalCostZero() {
        let statusline = StatuslineData(cost: CostInfo(totalCostUsd: 0.0))
        let session = SessionStatus(
            sessionId: "s1", statusline: statusline, lastUpdated: Date())
        #expect(session.totalCost == 0.0)
    }

    @Test("agentName with nil agent name field")
    func agentNameNilField() {
        let statusline = StatuslineData(agent: AgentInfo(name: nil))
        let session = SessionStatus(
            sessionId: "s1", statusline: statusline, lastUpdated: Date())
        #expect(session.agentName == nil)
    }

    @Test("projectDir prefers workspace.projectDir over currentDir")
    func projectDirPrefersProjectDir() {
        let statusline = StatuslineData(
            cwd: "/cwd",
            workspace: WorkspaceInfo(currentDir: "/current", projectDir: "/project")
        )
        let session = SessionStatus(
            sessionId: "s1", statusline: statusline, lastUpdated: Date())
        #expect(session.projectDir == "/project")
    }

    @Test("projectDir falls back to workspace.currentDir when projectDir is nil then cwd")
    func projectDirFallbackChain() {
        // workspace with only currentDir: falls through to cwd since projectDir is nil
        let statusline = StatuslineData(
            cwd: "/cwd",
            workspace: WorkspaceInfo(currentDir: "/current")
        )
        let session = SessionStatus(
            sessionId: "s1", statusline: statusline, lastUpdated: Date())
        // projectDir = workspace?.projectDir ?? cwd = nil ?? "/cwd" = "/cwd"
        #expect(session.projectDir == "/cwd")
    }

    // MARK: - Mutable statusline

    @Test("SessionStatus statusline can be updated")
    func mutableStatusline() {
        var session = SessionStatus(
            sessionId: "s1",
            statusline: StatuslineData(model: ModelInfo(id: "opus")),
            lastUpdated: Date(timeIntervalSince1970: 1700000000)
        )
        #expect(session.modelName == "opus")

        session.statusline = StatuslineData(
            model: ModelInfo(id: "sonnet", displayName: "Sonnet 4.6")
        )
        session.lastUpdated = Date(timeIntervalSince1970: 1700001000)

        #expect(session.modelName == "Sonnet 4.6")
    }

    // MARK: - All computed properties on single instance

    @Test("All computed properties with full data")
    func allComputedProperties() {
        let statusline = StatuslineData(
            cwd: "/cwd",
            model: ModelInfo(id: "claude-opus-4-6", displayName: "Opus 4.6"),
            workspace: WorkspaceInfo(projectDir: "/project"),
            cost: CostInfo(totalCostUsd: 1.5),
            contextWindow: ContextWindowInfo(usedPercentage: 85),
            agent: AgentInfo(name: "main-agent")
        )
        let session = SessionStatus(
            sessionId: "s1", statusline: statusline, lastUpdated: Date())

        #expect(session.id == "s1")
        #expect(session.modelName == "Opus 4.6")
        #expect(session.contextUsedPercent == 85)
        #expect(session.totalCost == 1.5)
        #expect(session.projectDir == "/project")
        #expect(session.agentName == "main-agent")
    }

    // MARK: - Snapshots Additional

    @Test("snapshot minimal SessionStatus dump")
    func snapshotMinimalSessionStatus() {
        let session = SessionStatus(
            sessionId: "sess-min",
            statusline: StatuslineData(),
            lastUpdated: Date(timeIntervalSince1970: 1700000000)
        )
        assertInlineSnapshot(of: session, as: .dump) {
            """
            ▿ SessionStatus
              - lastUpdated: 2023-11-14T22:13:20Z
              - sessionId: "sess-min"
              ▿ statusline: StatuslineData
                - agent: Optional<AgentInfo>.none
                - contextWindow: Optional<ContextWindowInfo>.none
                - cost: Optional<CostInfo>.none
                - cwd: Optional<String>.none
                - exceedsContextLimit: Optional<Bool>.none
                - model: Optional<ModelInfo>.none
                - sessionId: Optional<String>.none
                - transcriptPath: Optional<String>.none
                - version: Optional<String>.none
                - workspace: Optional<WorkspaceInfo>.none

            """
        }
    }

    // MARK: - Snapshot (full)

    @Test("snapshot SessionStatus dump")
    func snapshotSessionStatus() {
        let statusline = StatuslineData(
            cwd: "/home/user/project",
            sessionId: "sess-snap",
            model: ModelInfo(id: "claude-opus-4-6", displayName: "Opus 4.6"),
            cost: CostInfo(totalCostUsd: 0.05),
            contextWindow: ContextWindowInfo(usedPercentage: 78),
            agent: AgentInfo(name: "task-agent")
        )
        let session = SessionStatus(
            sessionId: "sess-snap",
            statusline: statusline,
            lastUpdated: Date(timeIntervalSince1970: 1700000000)
        )

        assertInlineSnapshot(of: session, as: .dump) {
            """
            ▿ SessionStatus
              - lastUpdated: 2023-11-14T22:13:20Z
              - sessionId: "sess-snap"
              ▿ statusline: StatuslineData
                ▿ agent: Optional<AgentInfo>
                  ▿ some: AgentInfo
                    ▿ name: Optional<String>
                      - some: "task-agent"
                ▿ contextWindow: Optional<ContextWindowInfo>
                  ▿ some: ContextWindowInfo
                    - contextWindowSize: Optional<Int>.none
                    - currentUsage: Optional<TokenUsage>.none
                    - remainingPercentage: Optional<Int>.none
                    - totalInputTokens: Optional<Int>.none
                    - totalOutputTokens: Optional<Int>.none
                    ▿ usedPercentage: Optional<Int>
                      - some: 78
                ▿ cost: Optional<CostInfo>
                  ▿ some: CostInfo
                    - totalApiDurationMs: Optional<Int>.none
                    ▿ totalCostUsd: Optional<Double>
                      - some: 0.05
                    - totalDurationMs: Optional<Int>.none
                    - totalLinesAdded: Optional<Int>.none
                    - totalLinesRemoved: Optional<Int>.none
                ▿ cwd: Optional<String>
                  - some: "/home/user/project"
                - exceedsContextLimit: Optional<Bool>.none
                ▿ model: Optional<ModelInfo>
                  ▿ some: ModelInfo
                    ▿ displayName: Optional<String>
                      - some: "Opus 4.6"
                    - id: "claude-opus-4-6"
                ▿ sessionId: Optional<String>
                  - some: "sess-snap"
                - transcriptPath: Optional<String>.none
                - version: Optional<String>.none
                - workspace: Optional<WorkspaceInfo>.none

            """
        }
    }
}

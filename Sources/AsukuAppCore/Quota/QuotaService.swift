import Foundation

/// Owns the low-frequency, bounded quota reads (Codex rollout scan, Claude historical-cost scan),
/// guaranteeing single-flight and caching, and persisting the last-known snapshot to disk.
///
/// A dedicated `actor` (like `PendingRequestManager`) isolates all mutable cache/throttle state.
/// The heavy file IO runs in a detached utility task so it never blocks this actor's executor, and
/// concurrent callers coalesce onto the in-flight task rather than starting a second scan.
public actor QuotaService {
    private let fs: FileSystem
    private let pricing: PricingTable
    private let codexSessionsDir: String
    private let claudeProjectsDir: String
    private let snapshotPath: String
    private let costThrottle: TimeInterval
    private let costBudget: QuotaReader.Budget

    private var cachedCost: CostEstimate?
    private var costInFlight: Task<CostEstimate?, Never>?

    private var cachedCodexUsage: ProviderUsage?
    private var codexInFlight: Task<ProviderUsage?, Never>?

    public init(
        fs: FileSystem = LocalFileSystem(),
        pricing: PricingTable = .default,
        codexSessionsDir: String,
        claudeProjectsDir: String,
        snapshotPath: String = QuotaService.defaultSnapshotPath(),
        costThrottle: TimeInterval = 15 * 60,
        costBudget: QuotaReader.Budget = QuotaReader.Budget()
    ) {
        self.fs = fs
        self.pricing = pricing
        self.codexSessionsDir = codexSessionsDir
        self.claudeProjectsDir = claudeProjectsDir
        self.snapshotPath = snapshotPath
        self.costThrottle = costThrottle
        self.costBudget = costBudget
    }

    // MARK: - Codex quota

    /// Refresh the Codex quota observation. Single-flight: concurrent callers await one scan.
    public func refreshCodex(now: Date, staleAfter: TimeInterval = 15 * 60) async -> QuotaObservation {
        let usage = await scanCodex()
        guard let usage, usage.hasRateData else {
            return QuotaObservation(provider: .codex, state: .unavailable)
        }
        let observedAt = usage.observedAt ?? now
        return QuotaObservation(
            provider: .codex,
            state: QuotaObservation.freshnessState(usage: usage, observedAt: observedAt, now: now, staleAfter: staleAfter),
            usage: usage,
            observedAt: observedAt
        )
    }

    private func scanCodex() async -> ProviderUsage? {
        if let inFlight = codexInFlight { return await inFlight.value }
        let fs = self.fs
        let dir = self.codexSessionsDir
        let task = Task<ProviderUsage?, Never>.detached(priority: .utility) {
            QuotaReader.codexUsage(sessionsDir: dir, fs: fs)
        }
        codexInFlight = task
        let result = await task.value
        codexInFlight = nil
        if let result { cachedCodexUsage = result }
        return result
    }

    // MARK: - Claude historical cost

    /// Recompute the Claude historical-cost estimate. Within `costThrottle` of the last successful
    /// compute (and unless `force`), returns the cached estimate WITHOUT rescanning. Single-flight.
    public func refreshCost(now: Date, force: Bool = false) async -> CostEstimate? {
        if !force, let cached = cachedCost, now.timeIntervalSince(cached.computedAt) < costThrottle {
            return cached
        }
        if let inFlight = costInFlight { return await inFlight.value }

        let fs = self.fs
        let dir = self.claudeProjectsDir
        let pricing = self.pricing
        let budget = self.costBudget
        let task = Task<CostEstimate?, Never>.detached(priority: .utility) {
            QuotaReader.claudeCostEstimate(
                projectsDir: dir, fs: fs, pricing: pricing, budget: budget, now: now
            ) { Task.isCancelled }
        }
        costInFlight = task
        let result = await task.value
        costInFlight = nil
        if let result { cachedCost = result }
        return result
    }

    // MARK: - Lifecycle

    /// Cancel any in-flight scans (called on app stop). The cost scan observes `Task.isCancelled`
    /// and bails out promptly; the codex tail-scan is already tiny and finishes on its own.
    public func cancelInFlight() {
        costInFlight?.cancel()
        codexInFlight?.cancel()
    }

    // MARK: - Persistence (last-known snapshot)

    /// Persisted last-known quota (loaded on launch and shown as `.stale`). Never contains prompts.
    public func loadPersistedSnapshot() -> QuotaSnapshot? {
        guard fs.fileExists(at: snapshotPath), let data = try? fs.readData(at: snapshotPath) else {
            return nil
        }
        return try? JSONDecoder.quota.decode(QuotaSnapshot.self, from: data)
    }

    /// Persist the last-known snapshot atomically. Failures are swallowed (best-effort cache).
    public func persist(_ snapshot: QuotaSnapshot) {
        guard let data = try? JSONEncoder.quota.encode(snapshot) else { return }
        try? fs.writeAtomically(data, to: snapshotPath)
    }

    // MARK: - Defaults

    public static func defaultSnapshotPath() -> String {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("asuku/quota.json").path
    }

    public static func defaultCodexSessionsDir() -> String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions").path
    }

    public static func defaultClaudeProjectsDir() -> String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects").path
    }
}

extension JSONEncoder {
    fileprivate static var quota: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    fileprivate static var quota: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

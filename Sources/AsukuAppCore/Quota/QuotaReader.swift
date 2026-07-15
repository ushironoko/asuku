import Foundation

/// Bounded, injectable readers for the two locally-derived quota sources. Both take a `FileSystem`
/// seam so tests exercise them against a real temp directory; both are bounded so they never scan
/// the whole (multi-GB) log tree unbounded.
public enum QuotaReader {
    /// Bounds for the Claude historical-cost scan. Defaults keep a single pass cheap.
    public struct Budget: Sendable {
        /// Stop once this many total bytes have been read across files.
        public var maxTotalBytes: UInt64
        /// Stop after reading this many files (newest first).
        public var maxFiles: Int
        /// Skip any single file larger than this (pathological outlier guard).
        public var maxFileBytes: UInt64

        public init(
            // Defaults comfortably cover a typical ~/.claude/projects tree in one pass; a runaway
            // multi-GB tree still stops here and reports the result as `truncated`.
            maxTotalBytes: UInt64 = 1024 * 1024 * 1024,
            maxFiles: Int = 8000,
            maxFileBytes: UInt64 = 64 * 1024 * 1024
        ) {
            self.maxTotalBytes = maxTotalBytes
            self.maxFiles = maxFiles
            self.maxFileBytes = maxFileBytes
        }
    }

    /// Latest Codex 5h/weekly quota, found by tail-scanning the newest rollout files. Bounded by
    /// `maxFilesToScan` so a huge `~/.codex/sessions` tree is never fully parsed.
    public static func codexUsage(sessionsDir: String, fs: FileSystem, maxFilesToScan: Int = 8) -> ProviderUsage? {
        CodexRolloutParser.latestUsage(sessionsDir: sessionsDir, fs: fs, maxFilesToScan: maxFilesToScan)
    }

    /// Offline historical token-cost estimate over `~/.claude/projects/**/*.jsonl`.
    ///
    /// - Reads newest-first, one file at a time (so only one file's bytes are resident at once).
    /// - Honors `budget` (total bytes / file count / per-file cap) and `isCancelled` so a single
    ///   pass stays cheap and interruptible.
    /// - Returns nil when the directory has no matching files at all.
    public static func claudeCostEstimate(
        projectsDir: String,
        fs: FileSystem,
        pricing: PricingTable = .default,
        budget: Budget = Budget(),
        now: Date,
        isCancelled: () -> Bool = { false }
    ) -> CostEstimate? {
        let files = fs.filesRecursively(under: projectsDir, withSuffix: ".jsonl")
        guard !files.isEmpty else { return nil }

        var combined = ClaudeTokenRollup.zero
        var bytesRead: UInt64 = 0
        var filesRead = 0
        var consideredFiles = 0
        var truncated = false

        for path in files {
            if isCancelled() { truncated = true; break }
            if filesRead >= budget.maxFiles || bytesRead >= budget.maxTotalBytes {
                truncated = true
                break
            }
            consideredFiles += 1
            // Skip a single pathologically large file, but don't call the whole scan truncated for it.
            if let size = fs.fileSize(at: path), size > budget.maxFileBytes { continue }

            // Read and process one file, then release its bytes before the next iteration.
            autoreleasepool {
                guard let data = try? fs.readData(at: path) else { return }
                bytesRead += UInt64(data.count)
                filesRead += 1
                combined.add(ClaudeJSONLParser.rollup(fromJSONL: data, pricing: pricing))
            }
        }

        combined.recomputeCost(pricing: pricing)
        let unknownModelCount = combined.byModel.keys.filter { pricing.price(forModel: $0) == nil }.count
        return CostEstimate(
            costUSD: combined.costUSD,
            computedAt: now,
            unknownModelCount: unknownModelCount,
            pricingVersion: pricing.version,
            truncated: truncated
        )
    }
}

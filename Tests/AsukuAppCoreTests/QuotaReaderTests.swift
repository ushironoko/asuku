import Foundation
import Testing

@testable import AsukuAppCore

@Suite("QuotaReader.claudeCostEstimate")
struct QuotaReaderCostTests {
    private let fs = LocalFileSystem()
    private let now = Date(timeIntervalSince1970: 1_772_000_000)

    private func tempDir() -> String {
        NSTemporaryDirectory() + "asuku-cost-\(UUID().uuidString)"
    }

    private func singleFileCost() throws -> Double {
        ClaudeJSONLParser.rollup(fromJSONL: try Fixture.data("claude-projects-sample.jsonl"), pricing: .default).costUSD
    }

    @Test("aggregates cost across multiple project files")
    func aggregates() throws {
        let dir = tempDir()
        let sample = try Fixture.data("claude-projects-sample.jsonl")
        try fs.writeAtomically(sample, to: dir + "/projA/a.jsonl")
        try fs.writeAtomically(sample, to: dir + "/projB/b.jsonl")

        let estimate = try #require(QuotaReader.claudeCostEstimate(projectsDir: dir, fs: fs, now: now))
        #expect(abs(estimate.costUSD - (try singleFileCost() * 2)) < 1e-9)
        #expect(estimate.pricingVersion == PricingTable.default.version)
        #expect(estimate.computedAt == now)
        #expect(estimate.truncated == false) // full pass under default budget
    }

    @Test("empty projects dir → nil")
    func emptyDir() {
        #expect(QuotaReader.claudeCostEstimate(projectsDir: tempDir(), fs: fs, now: now) == nil)
    }

    @Test("maxFiles budget stops early")
    func fileBudget() throws {
        let dir = tempDir()
        let sample = try Fixture.data("claude-projects-sample.jsonl")
        try fs.writeAtomically(sample, to: dir + "/a.jsonl")
        try fs.writeAtomically(sample, to: dir + "/b.jsonl")

        let budget = QuotaReader.Budget(maxTotalBytes: .max, maxFiles: 1, maxFileBytes: .max)
        let estimate = try #require(QuotaReader.claudeCostEstimate(projectsDir: dir, fs: fs, budget: budget, now: now))
        // Only one file counted → single-file cost, not double.
        #expect(abs(estimate.costUSD - (try singleFileCost())) < 1e-9)
        #expect(estimate.truncated == true) // stopped early at the file-count cap
    }

    @Test("per-file cap skip alone does not mark the scan truncated")
    func perFileSkipNotTruncated() throws {
        let dir = tempDir()
        try fs.writeAtomically(try Fixture.data("claude-projects-sample.jsonl"), to: dir + "/big.jsonl")
        let budget = QuotaReader.Budget(maxTotalBytes: .max, maxFiles: .max, maxFileBytes: 1)
        let estimate = try #require(QuotaReader.claudeCostEstimate(projectsDir: dir, fs: fs, budget: budget, now: now))
        #expect(estimate.truncated == false) // we considered every file; one was just skipped
    }

    @Test("isCancelled halts before any file is read")
    func cancelled() throws {
        let dir = tempDir()
        try fs.writeAtomically(try Fixture.data("claude-projects-sample.jsonl"), to: dir + "/a.jsonl")
        let estimate = try #require(
            QuotaReader.claudeCostEstimate(projectsDir: dir, fs: fs, now: now, isCancelled: { true })
        )
        #expect(estimate.costUSD == 0) // nothing read
    }

    @Test("per-file size cap skips oversized files")
    func perFileCap() throws {
        let dir = tempDir()
        try fs.writeAtomically(try Fixture.data("claude-projects-sample.jsonl"), to: dir + "/big.jsonl")
        let budget = QuotaReader.Budget(maxTotalBytes: .max, maxFiles: .max, maxFileBytes: 1) // 1 byte cap
        let estimate = try #require(QuotaReader.claudeCostEstimate(projectsDir: dir, fs: fs, budget: budget, now: now))
        #expect(estimate.costUSD == 0) // file skipped for exceeding the per-file cap
    }

    @Test("symlinked jsonl is not followed")
    func symlinkNotFollowed() throws {
        let dir = tempDir()
        let outside = tempDir()
        let sample = try Fixture.data("claude-projects-sample.jsonl")
        try fs.writeAtomically(sample, to: dir + "/real/a.jsonl")
        try fs.writeAtomically(sample, to: outside + "/target.jsonl")
        try FileManager.default.createDirectory(atPath: dir + "/real", withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: dir + "/real/link.jsonl", withDestinationPath: outside + "/target.jsonl"
        )
        let estimate = try #require(QuotaReader.claudeCostEstimate(projectsDir: dir, fs: fs, now: now))
        // Only the one real file is counted; the symlink is skipped.
        #expect(abs(estimate.costUSD - (try singleFileCost())) < 1e-9)
    }

    @Test("unknown models are counted in metadata")
    func unknownModels() throws {
        let dir = tempDir()
        let line = #"{"message":{"model":"mystery-model-1","usage":{"input_tokens":100,"output_tokens":50}}}"#
        try fs.writeAtomically(Data(line.utf8), to: dir + "/u.jsonl")
        let estimate = try #require(QuotaReader.claudeCostEstimate(projectsDir: dir, fs: fs, now: now))
        #expect(estimate.unknownModelCount == 1)
        #expect(estimate.costUSD == 0) // unknown model → no cost
    }
}

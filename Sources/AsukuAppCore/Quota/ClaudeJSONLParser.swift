// Vendored from quota-glance (github.com/ushironoko/quota-glance) @ 1ba693b, MIT License.
// Upstream: Core/Sources/QGParsing/ClaudeJSONLParser.swift.
// Flattened into AsukuAppCore (QG module split dropped) for the Quota tab integration.

import Foundation

public struct ModelTokens: Sendable, Equatable {
    public var inputTokens = 0
    public var outputTokens = 0
    public var cacheCreationInputTokens = 0
    public var cacheReadInputTokens = 0
}

/// Token + cost rollup from Claude Code session logs (the ccusage model). Estimate only.
public struct ClaudeTokenRollup: Sendable, Equatable {
    public var inputTokens = 0
    public var outputTokens = 0
    public var cacheCreationInputTokens = 0
    public var cacheReadInputTokens = 0
    public var byModel: [String: ModelTokens] = [:]
    public var costUSD: Double = 0

    public static let zero = ClaudeTokenRollup()

    /// Merge another rollup's token counts into this one (does not recompute cost).
    public mutating func add(_ other: ClaudeTokenRollup) {
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        cacheCreationInputTokens += other.cacheCreationInputTokens
        cacheReadInputTokens += other.cacheReadInputTokens
        for (model, tokens) in other.byModel {
            var mt = byModel[model] ?? ModelTokens()
            mt.inputTokens += tokens.inputTokens
            mt.outputTokens += tokens.outputTokens
            mt.cacheCreationInputTokens += tokens.cacheCreationInputTokens
            mt.cacheReadInputTokens += tokens.cacheReadInputTokens
            byModel[model] = mt
        }
    }

    /// Recompute `costUSD` from `byModel` using the given pricing table.
    public mutating func recomputeCost(pricing: PricingTable) {
        costUSD = byModel.reduce(0) { acc, entry in
            acc + pricing.cost(model: entry.key,
                               inputTokens: entry.value.inputTokens,
                               outputTokens: entry.value.outputTokens,
                               cacheCreationTokens: entry.value.cacheCreationInputTokens,
                               cacheReadTokens: entry.value.cacheReadInputTokens)
        }
    }
}

/// Parses `~/.claude/projects/**/*.jsonl`. Sums assistant-message token usage per model and
/// estimates cost offline. Non-usage lines are ignored; malformed lines are skipped (best-effort).
public enum ClaudeJSONLParser {
    private struct Line: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable {
                let input_tokens: Int?
                let output_tokens: Int?
                let cache_creation_input_tokens: Int?
                let cache_read_input_tokens: Int?
            }
            let model: String?
            let usage: Usage?
        }
        let message: Message?
    }

    public static func rollup(fromJSONL data: Data, pricing: PricingTable) -> ClaudeTokenRollup {
        var rollup = ClaudeTokenRollup.zero
        let decoder = JSONDecoder()
        let newline = UInt8(ascii: "\n")

        for slice in data.split(separator: newline, omittingEmptySubsequences: true) {
            guard
                let line = try? decoder.decode(Line.self, from: Data(slice)),
                let model = line.message?.model,
                let u = line.message?.usage
            else { continue }

            let it = u.input_tokens ?? 0
            let ot = u.output_tokens ?? 0
            let cc = u.cache_creation_input_tokens ?? 0
            let cr = u.cache_read_input_tokens ?? 0

            rollup.inputTokens += it
            rollup.outputTokens += ot
            rollup.cacheCreationInputTokens += cc
            rollup.cacheReadInputTokens += cr

            var mt = rollup.byModel[model] ?? ModelTokens()
            mt.inputTokens += it
            mt.outputTokens += ot
            mt.cacheCreationInputTokens += cc
            mt.cacheReadInputTokens += cr
            rollup.byModel[model] = mt
        }

        rollup.recomputeCost(pricing: pricing)
        return rollup
    }
}

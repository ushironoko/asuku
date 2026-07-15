// Vendored from quota-glance (github.com/ushironoko/quota-glance) @ 1ba693b, MIT License.
// Upstream: Core/Sources/QGParsing/PricingCost.swift.
// Flattened into AsukuAppCore (QG module split dropped) for the Quota tab integration.

import Foundation

/// Per-million-token prices for a model family (USD). Estimated.
public struct ModelPrice: Sendable, Equatable {
    public var inputPerMTok: Double
    public var outputPerMTok: Double
    public var cacheWritePerMTok: Double
    public var cacheReadPerMTok: Double

    public init(inputPerMTok: Double, outputPerMTok: Double, cacheWritePerMTok: Double, cacheReadPerMTok: Double) {
        self.inputPerMTok = inputPerMTok
        self.outputPerMTok = outputPerMTok
        self.cacheWritePerMTok = cacheWritePerMTok
        self.cacheReadPerMTok = cacheReadPerMTok
    }
}

/// Offline cost estimation table. Cost figures are ESTIMATES and intentionally versioned so the
/// table can be updated without shipping app logic. Unknown models cost 0 (policy: never guess).
public struct PricingTable: Sendable {
    /// Keyed by model-family prefix (e.g. "claude-opus-4" matches "claude-opus-4-8-...").
    public let prices: [String: ModelPrice]
    public let version: String

    public init(prices: [String: ModelPrice], version: String = "2026-06-16") {
        self.prices = prices
        self.version = version
    }

    public func cost(model: String, inputTokens: Int, outputTokens: Int,
                     cacheCreationTokens: Int, cacheReadTokens: Int) -> Double {
        guard let p = price(forModel: model) else { return 0 }
        let m = 1_000_000.0
        return Double(inputTokens) / m * p.inputPerMTok
            + Double(outputTokens) / m * p.outputPerMTok
            + Double(cacheCreationTokens) / m * p.cacheWritePerMTok
            + Double(cacheReadTokens) / m * p.cacheReadPerMTok
    }

    func price(forModel model: String) -> ModelPrice? {
        if let exact = prices[model] { return exact }
        // Longest matching family prefix wins (deterministic).
        let match = prices.keys
            .filter { model.hasPrefix($0) }
            .sorted { $0.count > $1.count }
            .first
        return match.flatMap { prices[$0] }
    }

    /// Estimated public Claude prices (USD / Mtok) as of the table version. Values are clearly
    /// labeled "estimated" in the UI.
    public static let `default` = PricingTable(prices: [
        "claude-opus-4":   ModelPrice(inputPerMTok: 15,  outputPerMTok: 75, cacheWritePerMTok: 18.75, cacheReadPerMTok: 1.50),
        "claude-sonnet-4": ModelPrice(inputPerMTok: 3,   outputPerMTok: 15, cacheWritePerMTok: 3.75,  cacheReadPerMTok: 0.30),
        "claude-haiku-4":  ModelPrice(inputPerMTok: 1,   outputPerMTok: 5,  cacheWritePerMTok: 1.25,  cacheReadPerMTok: 0.10),
    ])
}

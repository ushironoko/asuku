// Vendored from quota-glance (github.com/ushironoko/quota-glance) @ 1ba693b, MIT License.
// Upstream: Core/Sources/QGModels/Credits.swift.
// Flattened into AsukuAppCore (QG module split dropped) for the Quota tab integration.

import Foundation

/// Extra-usage / credit balance, where a provider exposes it (e.g. Codex `rate_limits.credits`).
public struct Credits: Sendable, Codable, Equatable, Hashable {
    public var hasCredits: Bool
    public var unlimited: Bool
    public var balance: Double?

    public init(hasCredits: Bool, unlimited: Bool, balance: Double? = nil) {
        self.hasCredits = hasCredits
        self.unlimited = unlimited
        self.balance = balance
    }
}

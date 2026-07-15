import Foundation

/// Pure display derivations for the Quota tab / menu bar (keeps Views dumb, keeps logic testable).
public enum QuotaDisplay {
    /// The single headline percentage for a provider: the max used% across its windows, rounded.
    /// Returns nil when there is no window data (so the caller can hide the summary).
    public static func menuBarPercent(_ usage: ProviderUsage?) -> Int? {
        guard let usage, let maxPercent = usage.windows.map(\.usedPercent).max() else { return nil }
        return Int(maxPercent.rounded())
    }

    /// The usage level for the headline percentage, for color coding. Nil when no data.
    public static func menuBarLevel(_ usage: ProviderUsage?) -> UsageLevel? {
        guard let usage, let maxPercent = usage.windows.map(\.usedPercent).max() else { return nil }
        return SnapshotDisplay.level(usedPercent: maxPercent)
    }
}

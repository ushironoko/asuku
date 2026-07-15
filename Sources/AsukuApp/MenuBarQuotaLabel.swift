import AsukuAppCore
import SwiftUI

/// The compact Claude quota % shown in the always-visible menu bar next to the icon.
/// Hidden entirely when there is no displayable quota; dimmed when the value is stale.
struct MenuBarQuotaLabel: View {
    let percent: Int?
    let level: UsageLevel?
    let isStale: Bool

    var body: some View {
        if let percent {
            Text("\(percent)%")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(color)
                .opacity(isStale ? 0.55 : 1)
        }
    }

    private var color: Color {
        switch level {
        case .critical: .red
        case .warn: .orange
        case .ok, .none: .primary
        }
    }
}

import AsukuAppCore
import SwiftUI

/// Compact Claude rate-limit (quota) display for the menu bar popover, shown in the session-detail
/// area above pending requests. Thin progress bars mirror the context-window bar style. Rendered
/// only when there is a displayable (available/stale) value.
struct MenuBarQuotaCompactView: View {
    let observation: QuotaObservation

    var body: some View {
        if let usage = observation.usage, usage.hasRateData, isDisplayable {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("\(observation.provider.displayName) limits")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if isStale {
                            Text("stale")
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.orange.opacity(0.15))
                                .foregroundStyle(.orange)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        Spacer()
                    }
                    ForEach(usage.windows, id: \.kind) { window in
                        QuotaWindowRow(window: window, now: context.date)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }

    private var isDisplayable: Bool {
        switch observation.state {
        case .available, .stale: true
        case .neverObserved, .unavailable, .error: false
        }
    }

    private var isStale: Bool {
        if case .stale = observation.state { return true }
        return false
    }
}

private struct QuotaWindowRow: View {
    let window: RateWindow
    let now: Date

    var body: some View {
        HStack(spacing: 6) {
            Text(window.kind.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            ProgressView(value: window.usedFraction)
                .tint(color)
            Text("\(Int(window.usedPercent.rounded()))%")
                .font(.caption2)
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)
            if let reset = window.resetsAt {
                Text("↻ \(SnapshotDisplay.compactCountdown(to: reset, now: now))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 58, alignment: .trailing)
            }
        }
    }

    private var color: Color {
        switch SnapshotDisplay.level(usedPercent: window.usedPercent) {
        case .ok: .green
        case .warn: .orange
        case .critical: .red
        }
    }
}

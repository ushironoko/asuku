import AsukuAppCore
import SwiftUI

/// Dashboard tab showing Claude/Codex subscription quota (5h/7d) plus cost. Claude quota arrives
/// live via the statusline hook; Codex quota + the historical cost estimate come from QuotaService.
struct QuotaTab: View {
    let claude: QuotaObservation
    let codex: QuotaObservation
    let costEstimate: CostEstimate?
    let dispatch: @MainActor (AppAction) -> Void

    private var isEmpty: Bool {
        claude.usage == nil && codex.usage == nil && costEstimate == nil
    }

    var body: some View {
        Group {
            if isEmpty {
                ContentUnavailableView(
                    "No Quota Data",
                    systemImage: "gauge",
                    description: Text(
                        "Claude quota appears once Claude Code renders its statusline "
                            + "(the asuku hook must be installed).\nCodex quota reads from ~/.codex/sessions."
                    )
                )
            } else {
                // Refresh the countdown labels (and re-render staleness) each minute.
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ProviderSection(observation: claude, now: context.date)
                            ProviderSection(observation: codex, now: context.date)
                            if let costEstimate {
                                HistoricalCostView(estimate: costEstimate)
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .onAppear { dispatch(.refreshQuotaCost) }
    }
}

// MARK: - Provider Section (tile + availability/freshness + measured session cost)

private struct ProviderSection: View {
    let observation: QuotaObservation
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(observation.provider.displayName).font(.subheadline).bold()
                StateBadge(state: observation.state)
                Spacer()
                if let observedAt = observation.observedAt, observation.usage != nil {
                    Text("updated \(observedAt, style: .relative) ago")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }

            if let usage = observation.usage {
                ProviderTileView(usage: usage, now: now)
                if observation.provider == .claude, let cost = usage.costUSD {
                    Text(String(format: "Current session (measured): $%.4f", cost))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var emptyText: String {
        switch observation.state {
        case .neverObserved:
            observation.provider == .claude
                ? "Run Claude Code to populate quota (needs the asuku statusline hook)."
                : "No Codex usage found in ~/.codex/sessions."
        case .unavailable:
            "No subscription quota reported (e.g. an API-key account)."
        case .error(let message):
            "Couldn't read quota: \(message)"
        case .available, .stale:
            ""
        }
    }
}

// MARK: - State badge

private struct StateBadge: View {
    let state: QuotaState

    var body: some View {
        if let label {
            Text(label)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.15))
                .foregroundStyle(color)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private var label: String? {
        switch state {
        case .stale: "stale"
        case .unavailable: "no quota"
        case .error: "error"
        case .available, .neverObserved: nil
        }
    }

    private var color: Color {
        switch state {
        case .stale: .orange
        case .error: .red
        default: .secondary
        }
    }
}

// MARK: - Historical cost estimate (separate from measured session cost)

private struct HistoricalCostView: View {
    let estimate: CostEstimate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Local token-cost estimate").font(.subheadline).bold()
            Text(String(format: "≈ $%.2f (est.)", estimate.costUSD))
                .font(.title3).monospacedDigit()
            Text(metaText)
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private var metaText: String {
        var parts = [
            estimate.truncated ? "partial (budget reached)" : "all local projects",
            "pricing \(estimate.pricingVersion)",
            "computed \(estimate.computedAt.formatted(date: .omitted, time: .shortened))",
        ]
        if estimate.unknownModelCount > 0 {
            parts.append("\(estimate.unknownModelCount) model(s) excluded")
        }
        return parts.joined(separator: " · ")
    }
}

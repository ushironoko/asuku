// Ported from quota-glance App/Sources/App/ProviderTileView.swift @ 1ba693b (MIT).
// Cost display was moved out to QuotaTab so measured session cost and the historical estimate can
// carry distinct labels; imports point at the vendored AsukuAppCore types.

import AsukuAppCore
import SwiftUI

/// A reusable provider tile: a ring per rate window with a reset countdown. Pure rendering — all
/// derivations come from the vendored display functions.
struct ProviderTileView: View {
    let usage: ProviderUsage
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(usage.provider.displayName).font(.headline)
                Spacer()
                if let plan = usage.planType {
                    Text(plan.uppercased()).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if usage.windows.isEmpty {
                Text("No live quota yet").font(.caption).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 16) {
                    ForEach(usage.windows, id: \.kind) { window in
                        WindowGauge(window: window, now: now)
                    }
                }
            }
            if let credits = usage.credits, credits.hasCredits {
                Text(creditsText(credits)).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func creditsText(_ credits: Credits) -> String {
        if credits.unlimited { return "Credits: unlimited" }
        if let balance = credits.balance { return String(format: "Credits: %.1f", balance) }
        return "Credits available"
    }
}

private struct WindowGauge: View {
    let window: RateWindow
    let now: Date

    private var color: Color {
        switch SnapshotDisplay.level(usedPercent: window.usedPercent) {
        case .ok: .green
        case .warn: .orange
        case .critical: .red
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: window.usedFraction)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(window.usedPercent.rounded()))%").font(.caption2).bold()
            }
            .frame(width: 52, height: 52)
            Text(window.kind.displayName).font(.caption2).foregroundStyle(.secondary)
            if let reset = window.resetsAt {
                Text("↻ \(SnapshotDisplay.compactCountdown(to: reset, now: now))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

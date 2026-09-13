import SwiftUI

struct StatsSettingsView: View {
    @Environment(StatsManager.self) private var stats
    @Environment(AppState.self) private var state
    @State private var confirmingReset = false

    var body: some View {
        SettingsForm {
            SettingsSection {
                HStack(spacing: 0) {
                    StatTile(title: "Keystrokes", value: stats.keystrokes)
                    Divider()
                    StatTile(title: "Mouse clicks", value: stats.clicks)
                    Divider()
                    StatTile(title: "Dings", value: stats.dings)
                }
                .padding(.vertical, 6)
            }

            SettingsSection("Favorite switches") {
                if stats.usageSorted.isEmpty {
                    Text("Start typing to see your favorites.").foregroundStyle(.secondary)
                } else {
                    let total = max(1, stats.usageSorted.reduce(0) { $0 + $1.count })
                    ForEach(stats.usageSorted, id: \.name) { row in
                        LabeledContent {
                            HStack(spacing: 12) {
                                UsageBar(fraction: Double(row.count) / Double(total))
                                Text("\(row.count * 100 / total)%")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                            }
                        } label: {
                            setLabel(named: row.name)
                        }
                    }
                }
            } footer: {
                Text("Counting since \(stats.firstTrackedAt.formatted(date: .abbreviated, time: .omitted)).")
            }

            ButtonRow {
                Button("Reset Stats…") { confirmingReset = true }
            }
        }
        .confirmationDialog("Reset all stats?", isPresented: $confirmingReset) {
            Button("Reset Stats", role: .destructive) { stats.reset() }
        } message: {
            Text("Keystroke, click and ding counts start again from zero.")
        }
    }

    /// Stats are kept by set name; show the set as it appears everywhere else.
    @ViewBuilder
    private func setLabel(named name: String) -> some View {
        if let set = state.availableSets.first(where: { $0.name == name }) {
            Text(set.displayName)
        } else {
            Text(name)
        }
    }
}

/// One counter in the row at the top of Stats.
private struct StatTile: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value.formatted())
                .font(.system(size: 26, weight: .regular))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct UsageBar: View {
    let fraction: Double

    var body: some View {
        Capsule()
            .fill(.quaternary)
            .frame(width: 140, height: 4)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Brand.accent.opacity(0.8))
                    .frame(width: max(4, 140 * fraction), height: 4)
            }
    }
}

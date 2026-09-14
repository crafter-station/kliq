import SwiftUI

struct StatsSettingsView: View {
    @Environment(StatsManager.self) private var stats
    @Environment(AppState.self) private var state
    @State private var confirmingReset = false

    var body: some View {
        SettingsForm {
            SettingsSection {
                HStack(spacing: 0) {
                    StatTile(symbol: "keyboard", title: "Keystrokes", value: stats.keystrokes)
                    Divider()
                    StatTile(symbol: "computermouse", title: "Mouse clicks", value: stats.clicks)
                    Divider()
                    StatTile(symbol: "bell", title: "Dings", value: stats.dings)
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
    let symbol: String
    let title: String
    let value: Int

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Brand.accent)
                .frame(width: 26, height: 26)
                .background(Brand.accent.opacity(0.10), in: Circle())
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value.formatted())
                .font(.system(size: 25, weight: .medium, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
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

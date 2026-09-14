import SwiftUI

/// The shared sampler for Kliq's seven sound profiles. Hovering auditions a profile
/// without changing the selection; clicking commits it and plays the same preview.
struct SoundBoard: View {
    @Environment(Settings.self) private var settings
    @Environment(AppState.self) private var state
    @Environment(AppController.self) private var controller
    @State private var hoveredName: String?
    @State private var hoverTask: Task<Void, Never>?

    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                Text("Hover to hear · click to choose")
                Spacer()
                if let selected = state.availableSets.first(where: { $0.name == settings.selectedSetName }) {
                    Label(selected.displayName, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Brand.accent)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if state.availableSets.isEmpty {
                ContentUnavailableView("No sounds found", systemImage: "speaker.slash")
                    .frame(maxWidth: .infinity, minHeight: compact ? 120 : 148)
            } else {
                VStack(spacing: compact ? 8 : 9) {
                    soundRow(Array(state.availableSets.prefix(4)))
                    soundRow(Array(state.availableSets.dropFirst(4)))
                        .padding(.horizontal, compact ? 52 : 68)
                }
            }
        }
        .padding(.vertical, 2)
        .onDisappear {
            hoverTask?.cancel()
            controller.cancelSoundPreview()
        }
    }

    private func soundRow(_ sets: [SoundSet]) -> some View {
        HStack(spacing: compact ? 8 : 9) {
            ForEach(sets) { set in
                SoundKey(
                    set: set,
                    isSelected: settings.selectedSetName == set.name,
                    isHovered: hoveredName == set.name,
                    compact: compact,
                    select: { select(set) },
                    hover: { hovering in hover(set, hovering: hovering) })
            }
        }
    }

    private func select(_ set: SoundSet) {
        hoverTask?.cancel()
        controller.selectSet(named: set.name, preview: true)
    }

    private func hover(_ set: SoundSet, hovering: Bool) {
        hoverTask?.cancel()
        if hovering {
            hoveredName = set.name
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(160))
                guard !Task.isCancelled, hoveredName == set.name else { return }
                controller.preview(set: set)
            }
        } else if hoveredName == set.name {
            hoveredName = nil
            controller.cancelSoundPreview()
        }
    }
}

/// A small physical key whose pressed motion previews the material behind its sound.
private struct SoundKey: View {
    let set: SoundSet
    let isSelected: Bool
    let isHovered: Bool
    let compact: Bool
    let select: () -> Void
    let hover: (Bool) -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: compact ? 5 : 7) {
                ZStack(alignment: .bottomTrailing) {
                    Keycap(label: String(set.displayName.prefix(1)), height: compact ? 30 : 36)
                        .offset(y: isHovered ? 2 : 0)
                    Image(systemName: isHovered ? "speaker.wave.2.fill" : "waveform")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Brand.capLegend)
                        .frame(width: 17, height: 17)
                        .background(Brand.capFaceTop, in: Circle())
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                        .offset(x: 6, y: 3)
                }
                Text(set.displayName)
                    .font((compact ? Font.caption : Font.subheadline).weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: compact ? 62 : 74)
            .background(tileBackground)
            .overlay(tileBorder)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover(perform: hover)
        .scaleEffect(isHovered ? 1.025 : 1)
        .shadow(color: Brand.accent.opacity(isHovered ? 0.14 : 0), radius: 7, y: 2)
        .animation(.snappy(duration: 0.18), value: isHovered)
        .animation(.snappy(duration: 0.18), value: isSelected)
        .help("Preview \(set.displayName)")
        .accessibilityLabel("\(set.displayName) switches")
        .accessibilityHint("Previews and selects this sound")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var tileBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isSelected ? Brand.accent.opacity(0.10) : Color.primary.opacity(isHovered ? 0.075 : 0.035))
    }

    private var tileBorder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(isSelected ? Brand.accent.opacity(0.88) : Color.primary.opacity(isHovered ? 0.28 : 0.1),
                          lineWidth: isSelected ? 1.5 : 0.5)
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Brand.accent)
                        .padding(7)
                }
            }
    }
}

import AppKit
import Combine
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, sound, sleep, stats, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .sound: "Sound"
        case .sleep: "Sleep"
        case .stats: "Stats"
        case .about: "About"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Status, startup and access"
        case .sound: "Shape how every key feels"
        case .sleep: "Stay quiet at the right moments"
        case .stats: "Your rhythm at a glance"
        case .about: "A tiny instrument for your Mac"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .sound: "speaker.wave.2.fill"
        case .sleep: "moon.zzz.fill"
        case .stats: "chart.bar.fill"
        case .about: "info"
        }
    }
}

/// Sidebar of pages on the left, the selected page on the right, as in System Settings.
/// The whole window is translucent; on macOS 26 the sidebar floats as a pane of glass.
struct SettingsRootView: View {
    @State private var page: SettingsPage = .general

    /// Height of the titlebar band; the traffic lights are centered in it.
    static let headerHeight: CGFloat = 64
    static let sidebarWidth: CGFloat = 184

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                header
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 780, height: 580)
        .background(WindowBackdrop())
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: SettingsSnapshots.selectPage)) { note in
            if let next = note.object as? SettingsPage { page = next }
        }
        #endif
    }

    @ViewBuilder
    private var sidebar: some View {
        if #available(macOS 26.0, *), LiquidGlass.isEnabled {
            // Inset from the window edges, with the traffic lights sitting inside it.
            sidebarRows
                .frame(width: Self.sidebarWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding([.top, .leading, .bottom], 8)
        } else {
            sidebarRows
                .frame(width: Self.sidebarWidth + 8)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(VisualEffectBackground(material: .sidebar))
                .overlay(alignment: .trailing) { Divider() }
        }
    }

    private var sidebarRows: some View {
        VStack(spacing: 2) {
            HStack(spacing: 9) {
                BrandMark(size: 26)
                    .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
                Text("Kliq")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 7)
            .padding(.bottom, 14)

            ForEach(SettingsPage.allCases) { item in
                SidebarRow(page: item, isSelected: item == page) { page = item }
            }
            Spacer(minLength: 16)
        }
        .padding(.horizontal, 10)
        // Rows start below the traffic lights.
        .padding(.top, Self.headerHeight - 2)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { step(by: -1) }
        .onKeyPress(.downArrow) { step(by: 1) }
    }

    private func step(by offset: Int) -> KeyPress.Result {
        let pages = SettingsPage.allCases
        guard let index = pages.firstIndex(of: page), pages.indices.contains(index + offset) else { return .ignored }
        page = pages[index + offset]
        return .handled
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(page.title)
                    .font(.title2.weight(.semibold))
                Text(page.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, SettingsMetrics.pageInset)
        .frame(height: Self.headerHeight)
        .overlay(alignment: .bottom) { Divider().opacity(0.45) }
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .general: GeneralSettingsView()
        case .sound: SoundSettingsView()
        case .sleep: SleepSettingsView()
        case .stats: StatsSettingsView()
        case .about: AboutView()
        }
    }
}

/// One page in the sidebar. A restrained brand tint makes the current location obvious.
private struct SidebarRow: View {
    let page: SettingsPage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: page.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Brand.accent : Color.secondary)
                    .frame(width: 20)
                Text(page.title)
                    .fontWeight(isSelected ? .medium : .regular)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 34)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Brand.accent.opacity(0.11))
                }
            }
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(Brand.accent)
                        .frame(width: 3, height: 16)
                        .offset(x: -1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.snappy(duration: 0.18), value: isSelected)
    }
}

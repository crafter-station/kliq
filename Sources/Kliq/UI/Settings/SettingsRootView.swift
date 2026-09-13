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
    static let headerHeight: CGFloat = 52
    static let sidebarWidth: CGFloat = 200

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                header
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 720, height: 540)
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
            ForEach(SettingsPage.allCases) { item in
                SidebarRow(page: item, isSelected: item == page) { page = item }
            }
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
            Text(page.title)
                .font(.title3.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, SettingsMetrics.pageInset + SettingsMetrics.rowInset)
        .frame(height: Self.headerHeight)
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

/// One page in the sidebar. The selection is a soft gray pill, never a color.
private struct SidebarRow: View {
    let page: SettingsPage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                IconTile(symbol: page.symbol, size: 20)
                Text(page.title)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .frame(height: 30)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.1))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

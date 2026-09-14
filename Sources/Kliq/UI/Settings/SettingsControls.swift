import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Glass

/// Liquid Glass is used on macOS 26 and later; macOS 15 gets frosted materials instead.
/// Debug builds can force the materials with KLIQ_NO_LIQUID_GLASS=1.
enum LiquidGlass {
    static let isEnabled: Bool = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["KLIQ_NO_LIQUID_GLASS"] == "1" { return false }
        #endif
        if #available(macOS 26.0, *) { return true }
        return false
    }()
}

enum SettingsMetrics {
    /// Space between the window edge and the cards.
    static let pageInset: CGFloat = 28
    static let sectionSpacing: CGFloat = 22
    /// Space between a card's edge and its rows.
    static let rowInset: CGFloat = 16
    static let cardRadius: CGFloat = 16
}

/// The translucent ground of a whole window: the desktop shows through, blurred.
struct WindowBackdrop: View {
    var material: NSVisualEffectView.Material = .underWindowBackground

    var body: some View {
        VisualEffectBackground(material: material)
            .ignoresSafeArea()
    }
}

extension View {
    /// A frosted card behind a group of rows: Liquid Glass on macOS 26, a thin material
    /// with a hairline edge on macOS 15.
    func settingsCard(cornerRadius: CGFloat = SettingsMetrics.cardRadius) -> some View {
        modifier(SettingsCard(cornerRadius: cornerRadius))
    }

    /// Row layout and the monochrome tint for controls inside settings cards.
    func settingsControlStyles() -> some View {
        toggleStyle(SettingsToggleStyle())
            .labeledContentStyle(SettingsRowStyle())
            .tint(Brand.accent)
    }
}

private struct SettingsCard: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *), LiquidGlass.isEnabled {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.thinMaterial, in: shape)
                .overlay(shape.fill(Color.primary.opacity(0.018)))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.045), radius: 8, y: 3)
        }
    }
}

/// Lets nearby glass shapes render together on macOS 26; passes content through before.
struct GlassGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *), LiquidGlass.isEnabled {
            GlassEffectContainer(spacing: 12) { content }
        } else {
            content
        }
    }
}

// MARK: - Page layout

/// A settings page: frosted cards in a scroll view, laid out like System Settings.
struct SettingsForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            GlassGroup {
                VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
                    content
                }
                .padding(.horizontal, SettingsMetrics.pageInset)
                .padding(.top, 4)
                .padding(.bottom, SettingsMetrics.pageInset)
            }
        }
        .withoutTopScrollEdge()
        .settingsControlStyles()
    }
}

private extension View {
    /// The page header already separates the scroll view from the titlebar, so the
    /// macOS 26 soft edge would only draw a seam under it.
    @ViewBuilder
    func withoutTopScrollEdge() -> some View {
        if #available(macOS 26.0, *) {
            scrollEdgeEffectHidden(true, for: .top)
        } else {
            self
        }
    }
}

/// A card of rows separated by hairlines, with an optional header above and footer below.
struct SettingsSection<Header: View, Content: View, Footer: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var header: Header
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, SettingsMetrics.rowInset)
            Group(subviews: content) { rows in
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        if row.id != rows.first?.id {
                            Divider().padding(.horizontal, SettingsMetrics.rowInset)
                        }
                        row
                            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                            .padding(.horizontal, SettingsMetrics.rowInset)
                            .padding(.vertical, 11)
                    }
                }
                .settingsCard()
            }
            footer
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, SettingsMetrics.rowInset)
        }
    }
}

extension SettingsSection where Header == EmptyView, Footer == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.init(content: content, header: { EmptyView() }, footer: { EmptyView() })
    }
}

extension SettingsSection where Header == Text, Footer == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(content: content, header: { Text(title) }, footer: { EmptyView() })
    }
}

extension SettingsSection where Header == EmptyView {
    init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.init(content: content, header: { EmptyView() }, footer: footer)
    }
}

extension SettingsSection where Header == Text {
    init(_ title: String, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.init(content: content, header: { Text(title) }, footer: footer)
    }
}

/// A row label: the first text is the title, any further text a quieter line below it.
struct RowLabel<Label: View>: View {
    @ViewBuilder var label: Label

    var body: some View {
        Group(subviews: label) { parts in
            VStack(alignment: .leading, spacing: 2) {
                ForEach(parts) { part in
                    if part.id == parts.first?.id {
                        part
                    } else {
                        part.font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Label on the left, control on the right, as in System Settings.
struct SettingsRowStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 16) {
            RowLabel { configuration.label }
            Spacer(minLength: 0)
            configuration.content
                .layoutPriority(1)
        }
    }
}

/// A toggle as a settings row: the label on the left, a small switch on the right.
struct SettingsToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 16) {
            RowLabel { configuration.label }
            Spacer(minLength: 0)
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

/// A quiet link that reveals a page's secondary settings below it.
struct MoreOptions<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Text("More options")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, SettingsMetrics.rowInset)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                content
                    .transition(.opacity)
            }
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: SettingsSnapshots.expandMoreOptions)) { _ in
            isExpanded = true
        }
        #endif
    }
}

// MARK: - Rows

/// The row at the top of a page: an icon, a sentence with an optional quieter line, and a control.
struct StatusCard<Icon: View, Accessory: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var icon: Icon
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 14) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            accessory
        }
        .padding(.vertical, 4)
    }
}

/// A one-line notice inside a card, such as a set that couldn't be played.
struct NoticeRow: View {
    let text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.circle")
        }
        .foregroundStyle(.secondary)
    }
}

/// Launch-at-login switch shared by Settings and the welcome guide. Disabled outside
/// /Applications, where macOS won't register the app.
struct LaunchAtLoginToggle: View {
    let title: String
    @State private var isOn = LaunchAtLogin.isEnabled
    @State private var awaitingApproval = LaunchAtLogin.isAwaitingApproval
    @State private var failed = false

    var body: some View {
        // A plain binding, so reverting after a failure doesn't re-enter the setter.
        Toggle(isOn: Binding(get: { isOn }, set: { update($0) })) {
            Text(title)
            if let note { Text(note) }
        }
        .disabled(InstallLocation.isOutsideApplications)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
        if awaitingApproval && !InstallLocation.isOutsideApplications {
            ButtonRow {
                Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
            }
        }
    }

    private var note: String? {
        if InstallLocation.isOutsideApplications {
            return "Available once Kliq is in Applications."
        } else if failed {
            return "macOS didn't allow it. Check Login Items in System Settings."
        } else if awaitingApproval {
            return "Waiting for your approval in System Settings."
        }
        return nil
    }

    private func update(_ on: Bool) {
        do {
            try LaunchAtLogin.set(on)
            isOn = on
            failed = false
        } catch {
            isOn = LaunchAtLogin.isEnabled
            failed = true
        }
        awaitingApproval = LaunchAtLogin.isAwaitingApproval
    }

    /// Approval happens in System Settings, so check again whenever Kliq comes back.
    private func refresh() {
        isOn = LaunchAtLogin.isEnabled
        awaitingApproval = LaunchAtLogin.isAwaitingApproval
    }
}

/// A slider row with a fixed-width track, so sliders in one section line up.
/// Shows either end labels (Lower … Higher) or the value as a percentage.
struct SettingSlider: View {
    let title: String
    var subtitle: String?
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var minimumLabel: String?
    var maximumLabel: String?

    private var showsPercent: Bool { minimumLabel == nil && maximumLabel == nil }

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                if let minimumLabel {
                    endLabel(minimumLabel, alignment: .trailing)
                }
                Slider(value: $value, in: range) { Text(title) }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: showsPercent ? 200 : 160)
                if let maximumLabel {
                    endLabel(maximumLabel, alignment: .leading)
                }
                if showsPercent {
                    Text("\(Int((value * 100).rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        } label: {
            Text(title)
            if let subtitle { Text(subtitle) }
        }
    }

    private func endLabel(_ text: String, alignment: Alignment) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(width: 56, alignment: alignment)
    }
}

/// A row of trailing buttons at the end of a section.
struct ButtonRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) {
            Spacer()
            content
        }
    }
}

// MARK: - Status text

/// Sleep status as a sentence, such as "Quiet while your microphone is in use".
enum QuietStatus {
    static func sentence(for reasons: [String]) -> String {
        let phrases = reasons.map { reason -> String in
            switch SleepManager.Trigger.allCases.first(where: { $0.reason == reason }) {
            case .microphone?: return "your microphone is in use"
            case .camera?: return "your camera is on"
            case .nowPlaying?: return "music is playing"
            case nil: return reason
            }
        }
        return phrases.isEmpty ? "Kliq is quiet" : "Quiet while \(phrases.formatted(.list(type: .and)))"
    }
}

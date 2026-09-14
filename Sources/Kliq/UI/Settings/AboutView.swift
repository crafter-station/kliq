import AppKit
import SwiftUI

struct AboutView: View {
    @Environment(\.openURL) private var openURL

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            BrandMark(size: 78)
                .shadow(color: .black.opacity(0.22), radius: 5, y: 3)
                .padding(.bottom, 14)
            Text("Kliq").font(.largeTitle.weight(.semibold))
            Text("Version \(version)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 2)
            Text("Make every keystroke feel alive.")
                .font(.title3.weight(.medium))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .padding(.top, 18)
            Text("Seven carefully selected sound profiles, mouse feedback, and automatic quiet time for calls.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .padding(.top, 8)
            HStack(spacing: 14) {
                feature("7 profiles", symbol: "waveform")
                feature("Private", symbol: "hand.raised")
                feature("Open source", symbol: "chevron.left.forwardslash.chevron.right")
            }
            .padding(.top, 20)
            // A plain button rather than Link, which always draws in the system link color.
            Button { openURL(URL(string: "https://kliq.crafter.run")!) } label: {
                Label("kliq.crafter.run", systemImage: "arrow.up.right")
            }
            .buttonStyle(.bordered)
            .pointerStyle(.link)
            .accessibilityAddTraits(.isLink)
            .padding(.top, 22)
            Text("Free and open source · MIT License")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 10)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Sits a little above center, balancing the page header.
        .padding(.bottom, SettingsRootView.headerHeight / 2)
    }

    private func feature(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color.primary.opacity(0.055), in: Capsule())
    }
}

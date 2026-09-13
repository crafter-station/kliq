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
            BrandMark(size: 96)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                .padding(.bottom, 16)
            Text("Kliq").font(.title.weight(.semibold))
            Text("Version \(version)")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 2)
            Text("Mechanical keyboard sounds for every keystroke and click, with smart sleep triggers so calls stay quiet.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .padding(.top, 16)
            Text("Free and open source under the MIT License. Bundled sounds are synthesized, not recordings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .padding(.top, 8)
            // A plain button rather than Link, which always draws in the system link color.
            Button { openURL(URL(string: "https://kliq.crafter.run")!) } label: {
                Text("kliq.crafter.run").underline()
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .accessibilityAddTraits(.isLink)
            .padding(.top, 24)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Sits a little above center, balancing the page header.
        .padding(.bottom, SettingsRootView.headerHeight / 2)
    }
}

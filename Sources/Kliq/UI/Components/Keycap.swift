import SwiftUI

/// A key legend drawn as a small keycap with a darker skirt: light on light, dark on dark.
struct Keycap: View {
    let label: String
    var height: CGFloat = 24

    var body: some View {
        let edge = max(2, (height * 0.12).rounded())
        let radius = height * 0.24
        Text(label)
            .font(.system(size: height * 0.5, weight: .medium, design: .rounded))
            .foregroundStyle(Brand.capLegend)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, height * 0.25)
            .frame(minWidth: height - 3, minHeight: height - edge - 1)
            .background(
                LinearGradient(colors: [Brand.capFaceTop, Brand.capFaceBottom], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: radius - 1, style: .continuous))
            .padding(.horizontal, 1.5)
            .padding(.top, 1)
            .padding(.bottom, edge)
            .background(
                LinearGradient(colors: [Brand.capSkirtTop, Brand.capSkirtBottom], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.14), radius: 1, y: 1)
    }
}

/// A shortcut such as ⌃⌥K as a row of keycaps.
struct KeycapRow: View {
    let keycaps: [String]
    var height: CGFloat = 24

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(keycaps.enumerated()), id: \.offset) { _, cap in
                Keycap(label: cap, height: height)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keycaps.joined())
    }
}

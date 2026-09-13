import SwiftUI

/// An SF Symbol on a small rounded tile with a soft monochrome gradient, as in System Settings.
struct IconTile: View {
    let symbol: String
    var size: CGFloat = 20

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.52, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Brand.tileGlyph)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [Brand.tileTop, Brand.tileBottom], startPoint: .top, endPoint: .bottom),
                        in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

/// A small dot and a short status, such as "● Allowed". Solid when all is well, hollow when not.
struct StatusIndicator: View {
    let text: String
    let isOK: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .strokeBorder(Color.primary.opacity(isOK ? 0 : 0.5), lineWidth: 1)
                .background(Circle().fill(isOK ? Brand.accent : .clear))
                .frame(width: 7, height: 7)
            Text(text).foregroundStyle(.secondary)
        }
    }
}

/// Hosts an NSVisualEffectView that blurs whatever is behind the window.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

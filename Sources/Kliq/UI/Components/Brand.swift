import AppKit
import SwiftUI

/// Kliq's palette: quiet neutrals with one warm signal borrowed from the app icon.
enum Brand {
    /// Active state, selection and primary actions. Everything else stays neutral.
    static let accent = Color(light: 0xD83A27, dark: 0xFF6B55)

    /// Icon tiles: a soft gray gradient with a glyph that contrasts with it.
    static let tileTop = Color(light: 0xFFFFFF, dark: 0x5E5E62)
    static let tileBottom = Color(light: 0xE6E6EA, dark: 0x3A3A3D)
    static let tileGlyph = Color(light: 0x1D1D1F, dark: 0xFFFFFF)

    /// Keycaps: light caps with dark legends in light mode, the reverse in dark mode.
    static let capFaceTop = Color(light: 0xFFFFFF, dark: 0x4B4B4F)
    static let capFaceBottom = Color(light: 0xF0F0F3, dark: 0x3C3C3F)
    static let capSkirtTop = Color(light: 0xD9D9DE, dark: 0x2B2B2E)
    static let capSkirtBottom = Color(light: 0xC3C3C9, dark: 0x1D1D1F)
    static let capLegend = Color(light: 0x1D1D1F, dark: 0xF2F2F4)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: opacity)
    }

    /// A color that follows the appearance: `light` in Aqua, `dark` in Dark Aqua.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

/// Kliq's app icon, for the welcome screen, About and the status card. Every view that
/// shows the logo goes through this one.
struct BrandMark: View {
    var size: CGFloat

    var body: some View {
        // The icon art sits on the macOS grid, an 824 pt tile on a 1024 pt canvas, so
        // draw the canvas larger than the frame to make the tile itself `size` wide.
        Image(nsImage: Self.icon)
            .resizable()
            .interpolation(.high)
            .frame(width: size * 1024 / 824, height: size * 1024 / 824)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    /// The bundled AppIcon; unbundled debug runs fall back to the drawn mark.
    private static let icon: NSImage = NSImage(named: "AppIcon") ?? KliqLogo.appIcon(size: 512)
}

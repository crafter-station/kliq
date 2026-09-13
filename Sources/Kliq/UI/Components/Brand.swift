import AppKit
import SwiftUI

/// Kliq's palette: monochrome. Black on light, white on dark, grays in between.
enum Brand {
    /// Switches, sliders, selection and prominent buttons.
    static let accent = Color(light: 0x111113, dark: 0xFFFFFF)

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

/// Kliq's logo as the app icon shows it: the white keycap mark from KliqLogo on a black
/// tile, in the icon's proportions. Every view that shows the logo goes through this one.
struct BrandMark: View {
    var size: CGFloat

    var body: some View {
        let s = size
        let tile = RoundedRectangle(cornerRadius: s * 0.225, style: .continuous)
        tile.fill(LinearGradient(colors: [Color(hex: 0x1F1F1F), Color(hex: 0x000000)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                // The icon insets the mark by 18.5% of the tile on each side.
                Image(nsImage: Self.mark(size: s * 0.63))
            }
            .frame(width: s, height: s)
            // Keeps the black tile's edge visible on dark backgrounds.
            .overlay(tile.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
            .accessibilityHidden(true)
    }

    private static func mark(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            KliqLogo.draw(in: rect, color: .white)
            return true
        }
    }
}

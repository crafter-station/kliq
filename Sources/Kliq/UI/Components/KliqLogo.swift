import AppKit

/// Kliq's mark: a flat keycap with a thick rim, a thin face outline, a depth wedge
/// along the bottom and right, and a K legend. Drawn from shapes so the app icon,
/// the menu bar glyph and in-app artwork all come from this one definition.
/// Tools/make_icon.swift compiles against this file to render AppIcon.icns.
enum KliqLogo {
    struct Style {
        /// The thin outline around the key's face; too fine to keep at menu bar size.
        var faceLine = true
        var letter = true
        /// Scales the K, which needs to be larger to stay legible at small sizes.
        var letterScale: CGFloat = 1
    }

    static let menuBarStyle = Style(faceLine: false, letter: true, letterScale: 1.25)

    /// Draws the mark in `color` inside the square `r` of the current graphics context.
    static func draw(in r: NSRect, color: NSColor, style: Style = Style()) {
        let u = r.width
        color.setFill()
        color.setStroke()

        // Rim: a rounded ring.
        let rim = u * 0.085
        let ring = NSBezierPath(roundedRect: r, xRadius: u * 0.17, yRadius: u * 0.17)
        ring.append(NSBezierPath(roundedRect: r.insetBy(dx: rim, dy: rim), xRadius: u * 0.10, yRadius: u * 0.10).reversed)
        ring.fill()

        // Face, set in from the rim with a clear gap.
        let face = r.insetBy(dx: u * 0.175, dy: u * 0.175)
        let faceLine = u * 0.024
        if style.faceLine {
            let outline = NSBezierPath(roundedRect: face, xRadius: u * 0.05, yRadius: u * 0.05)
            outline.lineWidth = faceLine
            outline.stroke()
        }

        // Depth wedge: an L band along the bottom and right of the face with 45° ends.
        // Its outer edge meets the outline's outer edge so the corner closes cleanly.
        let band = u * 0.085, taper = u * 0.12
        let grow = style.faceLine ? faceLine / 2 : 0
        let (x0, y0, x1, y1) = (face.minX, face.minY, face.maxX, face.maxY)
        let wedge = NSBezierPath()
        wedge.move(to: NSPoint(x: x0 + taper, y: y0 - grow))
        wedge.line(to: NSPoint(x: x1 + grow, y: y0 - grow))
        wedge.line(to: NSPoint(x: x1 + grow, y: y1 - taper))
        wedge.line(to: NSPoint(x: x1 - band, y: y1 - taper - band))
        wedge.line(to: NSPoint(x: x1 - band, y: y0 + band))
        wedge.line(to: NSPoint(x: x0 + taper + band, y: y0 + band))
        wedge.close()
        wedge.fill()

        guard style.letter else { return }
        // Geometric K, centered in the part of the face the wedge leaves open.
        let h = u * 0.30 * style.letterScale, weight = u * 0.082 * style.letterScale
        let cx = face.midX - band * 0.5, cy = face.midY + band * 0.5
        let x = cx - h * 0.31, bottom = cy - h / 2
        let k = NSBezierPath()
        k.move(to: NSPoint(x: x, y: bottom))
        k.line(to: NSPoint(x: x, y: bottom + h))
        k.move(to: NSPoint(x: x + h * 0.62, y: bottom + h))
        k.line(to: NSPoint(x: x + weight * 0.5, y: bottom + h * 0.46))
        k.line(to: NSPoint(x: x + h * 0.68, y: bottom))
        k.lineWidth = weight
        k.lineCapStyle = .butt
        k.lineJoinStyle = .miter
        k.stroke()
    }

    /// The app icon artwork: the white mark on a black rounded square, laid out on the
    /// macOS icon grid (824 of 1024 points), drawn into `canvas`.
    static func drawAppIcon(in canvas: NSRect) {
        let tile = canvas.insetBy(dx: canvas.width * 0.098, dy: canvas.width * 0.098)
        let shape = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
        NSGradient(starting: NSColor(white: 0.12, alpha: 1), ending: NSColor(white: 0, alpha: 1))?.draw(in: shape, angle: -90)
        NSColor(white: 1, alpha: 0.14).setStroke()
        shape.lineWidth = max(1, canvas.width * 0.004)
        shape.stroke()
        draw(in: tile.insetBy(dx: tile.width * 0.185, dy: tile.width * 0.185), color: .white)
    }

    /// The app icon at exactly `px` pixels, for the .iconset.
    static func appIconBitmap(px: Int) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: px, height: px)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        drawAppIcon(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// The app icon as a resolution-independent image, for in-app artwork.
    static func appIcon(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            drawAppIcon(in: rect)
            return true
        }
    }

    /// The menu bar glyph as a template image, so macOS tints it for the menu bar.
    static func menuBarTemplate(pointSize: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { rect in
            draw(in: rect.insetBy(dx: rect.width * 0.06, dy: rect.width * 0.06), color: .black, style: menuBarStyle)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Kliq"
        return image
    }
}

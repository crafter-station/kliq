import AppKit

/// Kliq's mark: a flat keycap with a thick rim, a thin face outline, a depth wedge
/// along the bottom and right, and a K legend. Drawn from shapes so the app icon,
/// the menu bar glyph and in-app artwork all come from this one definition.
/// Resources/AppIcon.svg is the master color artwork; this drawing also provides
/// the monochrome menu-bar mark and a faithful fallback for unbundled debug runs.
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

    /// The color app icon, drawn on the macOS icon grid (824 of 1024 points).
    static func drawAppIcon(in canvas: NSRect) {
        let scale = canvas.width / 1024
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: canvas.minX + x * scale, y: canvas.minY + (1024 - y) * scale)
        }
        func color(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
                    green: CGFloat((hex >> 8) & 0xff) / 255,
                    blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        }

        let tile = canvas.insetBy(dx: canvas.width * 0.098, dy: canvas.width * 0.098)
        let shape = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
        NSGraphicsContext.saveGraphicsState()
        let tileShadow = NSShadow()
        tileShadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
        tileShadow.shadowOffset = NSSize(width: 0, height: -12 * scale)
        tileShadow.shadowBlurRadius = 15 * scale
        tileShadow.set()
        NSGradient(starting: color(0xFBF8F1), ending: color(0xEEE8DE))?.draw(in: shape, angle: -90)
        NSGraphicsContext.restoreGraphicsState()
        color(0x31251F).withAlphaComponent(0.13).setStroke()
        shape.lineWidth = max(1, canvas.width * 0.004)
        shape.stroke()

        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: canvas.midX, yBy: canvas.midY)
        transform.rotate(byDegrees: 4)
        transform.translateX(by: -canvas.midX, yBy: -canvas.midY)
        transform.concat()

        let cap = NSBezierPath(roundedRect: NSRect(x: canvas.minX + 240 * scale, y: canvas.minY + 260 * scale,
                                                   width: 544 * scale, height: 496 * scale),
                               xRadius: 104 * scale, yRadius: 104 * scale)
        let depth = NSBezierPath(roundedRect: NSRect(x: canvas.minX + 258 * scale, y: canvas.minY + 238 * scale,
                                                     width: 544 * scale, height: 496 * scale),
                                 xRadius: 104 * scale, yRadius: 104 * scale)
        NSGraphicsContext.saveGraphicsState()
        let keyShadow = NSShadow()
        keyShadow.shadowColor = color(0x35140F).withAlphaComponent(0.20)
        keyShadow.shadowOffset = NSSize(width: 0, height: -12 * scale)
        keyShadow.shadowBlurRadius = 10 * scale
        keyShadow.set()
        color(0x273A5D).setFill()
        depth.fill()
        NSGraphicsContext.restoreGraphicsState()
        color(0xC93B31).setFill()
        cap.fill()

        NSGraphicsContext.saveGraphicsState()
        cap.addClip()
        color(0xF5B92E).setStroke()
        let topFlash = NSBezierPath()
        topFlash.move(to: point(267, 352))
        topFlash.curve(to: point(500, 298), controlPoint1: point(345, 310), controlPoint2: point(422, 295))
        topFlash.lineWidth = 25 * scale
        topFlash.lineCapStyle = .round
        topFlash.stroke()
        let bottomFlash = NSBezierPath()
        bottomFlash.move(to: point(618, 748))
        bottomFlash.curve(to: point(771, 654), controlPoint1: point(682, 728), controlPoint2: point(733, 696))
        bottomFlash.lineWidth = 24 * scale
        bottomFlash.lineCapStyle = .round
        bottomFlash.stroke()
        NSGraphicsContext.restoreGraphicsState()

        let face = NSBezierPath(roundedRect: NSRect(x: canvas.minX + 310 * scale, y: canvas.minY + 368 * scale,
                                                    width: 404 * scale, height: 340 * scale),
                                xRadius: 72 * scale, yRadius: 72 * scale)
        NSGradient(starting: color(0xF05242), ending: color(0xDF3E34))?.draw(in: face, angle: -45)
        color(0xFF7765).withAlphaComponent(0.62).setStroke()
        face.lineWidth = 7 * scale
        face.stroke()

        let letter = NSBezierPath()
        letter.move(to: point(435, 392))
        letter.line(to: point(435, 580))
        letter.move(to: point(565, 390))
        letter.line(to: point(463, 487))
        letter.line(to: point(574, 581))
        letter.lineWidth = 48 * scale
        letter.lineCapStyle = .square
        letter.lineJoinStyle = .miter
        color(0xF8F3E9).setStroke()
        letter.stroke()
        NSGraphicsContext.restoreGraphicsState()
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

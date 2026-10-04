import AppKit

/// The menu bar glyph: a porthole frame with four bolts and a wave behind the glass.
/// Drawn as a template image so it follows the menu bar's light/dark appearance.
enum MenuBarIcon {
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let center = CGPoint(x: rect.midX, y: rect.midY)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setFillColor(NSColor.black.cgColor)

            // Frame
            let ringRadius: CGFloat = 5.7
            ctx.setLineWidth(2.1)
            ctx.addArc(center: center, radius: ringRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
            ctx.strokePath()

            // Bolts, fused to the outer edge of the frame
            for i in 0..<4 {
                let angle = CGFloat(i) * .pi / 2 + .pi / 4
                let p = CGPoint(x: center.x + cos(angle) * 6.9, y: center.y + sin(angle) * 6.9)
                ctx.fillEllipse(in: CGRect(x: p.x - 1.35, y: p.y - 1.35, width: 2.7, height: 2.7))
            }

            // Wave behind the glass
            ctx.setLineWidth(1.5)
            ctx.setLineCap(.round)
            let y = center.y - 0.6
            ctx.move(to: CGPoint(x: center.x - 3.1, y: y))
            ctx.addCurve(to: CGPoint(x: center.x, y: y),
                         control1: CGPoint(x: center.x - 2.3, y: y + 2.2),
                         control2: CGPoint(x: center.x - 0.8, y: y + 2.2))
            ctx.addCurve(to: CGPoint(x: center.x + 3.1, y: y),
                         control1: CGPoint(x: center.x + 0.8, y: y - 2.2),
                         control2: CGPoint(x: center.x + 2.3, y: y - 2.2))
            ctx.strokePath()
            return true
        }
        image.isTemplate = true
        return image
    }()
}

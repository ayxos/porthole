// Generates AppIcon.icns: a brass porthole looking out on the sea.
// Usage: swift scripts/make-icon.swift [output.icns]
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("Porthole-\(UUID().uuidString).iconset")
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

func circle(_ c: CGPoint, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
}

func wave(y: CGFloat, amplitude: CGFloat, wavelength: CGFloat, from x0: CGFloat, to x1: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: x0, y: y))
    var x = x0
    while x < x1 {
        path.curve(to: NSPoint(x: x + wavelength, y: y),
                   controlPoint1: NSPoint(x: x + wavelength * 0.25, y: y + amplitude * 1.8),
                   controlPoint2: NSPoint(x: x + wavelength * 0.75, y: y - amplitude * 1.8))
        x += wavelength
    }
    return path
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gc
    let ctx = gc.cgContext
    let s = CGFloat(pixels)
    let c = CGPoint(x: s / 2, y: s / 2)

    // Background squircle (macOS icon grid: body is 80% of the canvas)
    let body = CGRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let bg = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.035,
                  color: NSColor.black.withAlphaComponent(0.4).cgColor)
    rgb(10, 24, 48).setFill(); bg.fill()
    ctx.restoreGState()
    NSGradient(colors: [rgb(18, 52, 96), rgb(8, 22, 46)])!.draw(in: bg, angle: -90)

    // Soft glow behind the porthole
    ctx.saveGState()
    bg.addClip()
    NSGradient(colors: [rgb(60, 140, 200, 0.35), rgb(60, 140, 200, 0)])!
        .draw(in: circle(c, s * 0.42), relativeCenterPosition: .zero)
    ctx.restoreGState()

    // Brass ring
    let outerR = s * 0.305
    let innerR = s * 0.215
    let ring = circle(c, outerR)
    ring.appendOval(in: CGRect(x: c.x - innerR, y: c.y - innerR, width: innerR * 2, height: innerR * 2))
    ring.windingRule = .evenOdd
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.03,
                  color: NSColor.black.withAlphaComponent(0.55).cgColor)
    rgb(190, 140, 55).setFill(); ring.fill()
    ctx.restoreGState()
    NSGradient(colors: [rgb(250, 222, 140), rgb(205, 152, 58), rgb(130, 88, 26), rgb(228, 186, 96)])!
        .draw(in: ring, angle: -65)
    // bevel lines
    ctx.saveGState()
    rgb(255, 240, 190, 0.55).setStroke()
    let bevelOuter = circle(c, outerR - s * 0.006); bevelOuter.lineWidth = s * 0.006; bevelOuter.stroke()
    rgb(70, 45, 10, 0.6).setStroke()
    let bevelInner = circle(c, innerR + s * 0.006); bevelInner.lineWidth = s * 0.008; bevelInner.stroke()
    ctx.restoreGState()

    // Sea behind the glass
    let sea = circle(c, innerR)
    NSGradient(colors: [rgb(96, 190, 235), rgb(24, 104, 176), rgb(8, 48, 104)])!
        .draw(in: sea, relativeCenterPosition: NSPoint(x: -0.35, y: 0.45))
    ctx.saveGState()
    sea.addClip()
    for (i, offset) in [0.02, -0.07, -0.16].enumerated() {
        let w = wave(y: c.y + s * offset, amplitude: s * 0.012, wavelength: s * 0.11,
                     from: c.x - innerR - s * 0.05, to: c.x + innerR + s * 0.05)
        w.lineWidth = s * 0.016
        w.lineCapStyle = .round
        rgb(255, 255, 255, 0.62 - CGFloat(i) * 0.17).setStroke()
        w.stroke()
    }
    // glass highlight
    let highlight = NSBezierPath()
    highlight.appendArc(withCenter: c, radius: innerR * 0.78, startAngle: 110, endAngle: 165)
    highlight.lineWidth = s * 0.022
    highlight.lineCapStyle = .round
    rgb(255, 255, 255, 0.55).setStroke()
    highlight.stroke()
    ctx.restoreGState()

    // Bolts around the frame
    let boltR = s * 0.017
    let boltRadius = (outerR + innerR) / 2
    for i in 0..<8 {
        let a = CGFloat(i) * .pi / 4 + .pi / 8
        let p = CGPoint(x: c.x + cos(a) * boltRadius, y: c.y + sin(a) * boltRadius)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.003), blur: s * 0.006,
                      color: NSColor.black.withAlphaComponent(0.6).cgColor)
        rgb(120, 80, 24).setFill(); circle(p, boltR).fill()
        ctx.restoreGState()
        rgb(255, 232, 170, 0.8).setFill()
        circle(CGPoint(x: p.x - boltR * 0.25, y: p.y + boltR * 0.3), boltR * 0.42).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let variants: [(String, Int)] = [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
    ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
    ("512x512", 512), ("512x512@2x", 1024),
]
for (name, px) in variants {
    try! render(pixels: px).write(to: iconset.appendingPathComponent("icon_\(name).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output]
try! iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
if iconutil.terminationStatus == 0 {
    print("wrote \(output)")
} else {
    print("iconutil failed with status \(iconutil.terminationStatus)")
    exit(1)
}

// Renders docs/social-preview.png (1280x640) for the GitHub repository's social preview.
// Usage: swiftc -O -sdk <sdk> scripts/make-social-preview.swift -o make-social-preview && ./make-social-preview
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/social-preview.png"
let width = 1280, height = 640

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
let gc = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gc
let ctx = gc.cgContext
let canvas = NSRect(x: 0, y: 0, width: width, height: height)

// Background
NSGradient(colors: [rgb(20, 56, 104), rgb(8, 20, 44)])!.draw(in: canvas, angle: -30)
ctx.saveGState()
NSGradient(colors: [rgb(70, 160, 220, 0.28), rgb(70, 160, 220, 0)])!
    .draw(in: NSBezierPath(ovalIn: NSRect(x: -120, y: 120, width: 760, height: 760)), relativeCenterPosition: .zero)
ctx.restoreGState()

// Icon
if let icon = NSImage(contentsOfFile: "Resources/AppIcon.icns") {
    icon.draw(in: NSRect(x: 64, y: 392, width: 190, height: 190), from: .zero, operation: .sourceOver, fraction: 1)
}

// Title and tagline
let title = NSAttributedString(string: "Porthole", attributes: [
    .font: NSFont.systemFont(ofSize: 84, weight: .bold), .foregroundColor: NSColor.white,
])
title.draw(at: NSPoint(x: 262, y: 440))

let paragraph = NSMutableParagraphStyle()
paragraph.lineSpacing = 6
let tagline = NSAttributedString(string: "See what's listening on your Mac's ports.\nOpen it. Understand it. Kill it.", attributes: [
    .font: NSFont.systemFont(ofSize: 34, weight: .medium), .foregroundColor: rgb(226, 236, 248),
    .paragraphStyle: paragraph,
])
tagline.draw(in: NSRect(x: 68, y: 250, width: 660, height: 120))

// Chips
var x: CGFloat = 68
for text in ["macOS 14+", "Native Swift", "2 MB", "Open source, MIT"] {
    let label = NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: 20, weight: .semibold), .foregroundColor: rgb(236, 242, 250),
    ])
    let size = label.size()
    let chip = NSRect(x: x, y: 176, width: size.width + 34, height: 44)
    rgb(255, 255, 255, 0.12).setFill()
    NSBezierPath(roundedRect: chip, xRadius: 22, yRadius: 22).fill()
    label.draw(at: NSPoint(x: chip.minX + 17, y: chip.minY + 10))
    x = chip.maxX + 12
}

let footer = NSAttributedString(string: "github.com/ayxos/porthole", attributes: [
    .font: NSFont.monospacedSystemFont(ofSize: 22, weight: .medium), .foregroundColor: rgb(170, 196, 226),
])
footer.draw(at: NSPoint(x: 70, y: 96))

// Screenshot, bleeding off the bottom-right
if let shot = NSImage(contentsOfFile: "docs/screenshot-list.png") {
    let targetWidth: CGFloat = 470
    let scale = targetWidth / shot.size.width
    let frame = NSRect(x: 780, y: -40, width: targetWidth, height: shot.size.height * scale)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 40, color: NSColor.black.withAlphaComponent(0.55).cgColor)
    rgb(40, 40, 40).setFill()
    NSBezierPath(roundedRect: frame, xRadius: 22, yRadius: 22).fill()
    ctx.restoreGState()
    ctx.saveGState()
    NSBezierPath(roundedRect: frame, xRadius: 22, yRadius: 22).addClip()
    shot.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
    ctx.restoreGState()
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")

// Renders Linky's 1024×1024 app icon: a graphite squircle with a white link glyph.
// Usage: swift scripts/make-icon.swift <out.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: 824pt body centered in 1024 canvas.
let inset: CGFloat = 100
let body = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let path = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

// Soft drop shadow
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor.black.setFill()
path.fill()
NSGraphicsContext.restoreGraphicsState()

// Graphite gradient
NSGradient(colors: [NSColor(white: 0.24, alpha: 1), NSColor(white: 0.07, alpha: 1)])!
    .draw(in: path, angle: -90)

// Hairline highlight on the top edge
NSGraphicsContext.saveGraphicsState()
path.addClip()
NSColor.white.withAlphaComponent(0.10).setStroke()
let rim = NSBezierPath(roundedRect: body.insetBy(dx: 2, dy: 2), xRadius: 183, yRadius: 183)
rim.lineWidth = 4
rim.stroke()
NSGraphicsContext.restoreGraphicsState()

// Link glyph
let config = NSImage.SymbolConfiguration(pointSize: 400, weight: .semibold)
    .applying(.init(paletteColors: [.white]))
if let glyph = NSImage(systemSymbolName: "link", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
    let g = glyph.size
    let rect = NSRect(x: (size - g.width) / 2, y: (size - g.height) / 2, width: g.width, height: g.height)
    glyph.draw(in: rect)
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))

// Draws the Margin app icon (1024px PNG). Usage: swift make_icon.swift out.png
import Cocoa

let size: CGFloat = 1024
// A chunky hooked mark: across the top, then down the right side.
func quoteMark(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
    let q = NSBezierPath()
    q.move(to: NSPoint(x: cx - r, y: cy + 0.45 * r))
    q.appendArc(from: NSPoint(x: cx + 0.5 * r, y: cy + 0.45 * r), to: NSPoint(x: cx + 0.5 * r, y: cy - r), radius: 0.55 * r)
    q.line(to: NSPoint(x: cx + 0.5 * r, y: cy - r))
    q.lineWidth = 1.0 * r
    q.lineJoinStyle = .round
    q.stroke()
}
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let box = NSRect(x: 100, y: 100, width: 824, height: 824)
let s = box.width
let p = { (x: CGFloat, y: CGFloat) in NSPoint(x: box.minX + x * s, y: box.minY + y * s) }
let squircle = NSBezierPath(roundedRect: box, xRadius: 186, yRadius: 186)

// Soft drop shadow under the tile
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.set()
NSColor.white.setFill()
squircle.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
squircle.addClip()
NSGradient(starting: NSColor(white: 0.97, alpha: 1), ending: NSColor(white: 0.86, alpha: 1))!.draw(in: box, angle: -90)

// The dark hill
let hill = NSBezierPath()
hill.move(to: p(0, 0))
hill.line(to: p(0, 0.52))
hill.curve(to: p(0.40, 0.76), controlPoint1: p(0.10, 0.65), controlPoint2: p(0.24, 0.76))
hill.curve(to: p(0.75, 0.47), controlPoint1: p(0.59, 0.76), controlPoint2: p(0.66, 0.61))
hill.curve(to: p(1, 0.31), controlPoint1: p(0.83, 0.35), controlPoint2: p(0.92, 0.31))
hill.line(to: p(1, 0))
hill.close()
NSGradient(starting: NSColor(white: 0.13, alpha: 1), ending: NSColor(white: 0.02, alpha: 1))!.draw(in: hill, angle: -90)

// Closing quote marks that read as two happy eyes
NSColor.white.setStroke()
for x in [0.30, 0.50] as [CGFloat] {
    let c = p(x, 0.52)
    quoteMark(c.x, c.y, 0.07 * s)
}
NSGraphicsContext.restoreGraphicsState()

// Glassy rim
NSColor.white.withAlphaComponent(0.55).setStroke()
let rim = NSBezierPath(roundedRect: box.insetBy(dx: 3, dy: 3), xRadius: 183, yRadius: 183)
rim.lineWidth = 6
rim.stroke()

NSGraphicsContext.current?.flushGraphics()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))

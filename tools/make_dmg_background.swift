// Draws the installer window's background: tools/make_dmg_background.swift <out.png> <scale>
import AppKit

let out = CommandLine.arguments[1]
let scale = CGFloat(Double(CommandLine.arguments[2]) ?? 1)
let W: CGFloat = 640, H: CGFloat = 420
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
// Flip so y grows downwards, like Finder's icon positions.
ctx.translateBy(x: 0, y: H)
ctx.scaleBy(x: 1, y: -1)

NSColor(srgbRed: 0.985, green: 0.983, blue: 0.978, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()

// The same soft glow the app has behind its header.
func glow(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ c: NSColor) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [c.cgColor, c.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
}
glow(150, 20, 300, NSColor(srgbRed: 1, green: 0.69, blue: 0.48, alpha: 0.30))
glow(500, 0, 320, NSColor(srgbRed: 1, green: 0.56, blue: 0.69, alpha: 0.24))
glow(330, 430, 260, NSColor(srgbRed: 0.47, green: 0.67, blue: 1, alpha: 0.08))

func text(_ s: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let p = NSMutableParagraphStyle()
    p.alignment = .center
    let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: p, .kern: size > 18 ? -0.4 : 0]
    let str = NSAttributedString(string: s, attributes: a)
    // Text draws upright in a flipped context.
    NSGraphicsContext.saveGraphicsState()
    let flipped = NSGraphicsContext(cgContext: ctx, flipped: true)
    NSGraphicsContext.current = flipped
    str.draw(in: NSRect(x: 0, y: y, width: W, height: size * 1.5))
    NSGraphicsContext.restoreGraphicsState()
}
text("Install Margin", y: 38, size: 26, weight: .bold, color: NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1))
text("Drag Margin into your Applications folder", y: 76, size: 13.5, weight: .regular, color: NSColor(srgbRed: 0.43, green: 0.43, blue: 0.45, alpha: 1))

// Arrow from the app to the Applications folder.
ctx.setStrokeColor(NSColor(srgbRed: 0.55, green: 0.55, blue: 0.58, alpha: 0.75).cgColor)
ctx.setLineWidth(2.4)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.setLineDash(phase: 0, lengths: [0.01, 7.5])
ctx.move(to: CGPoint(x: 262, y: 206))
ctx.addQuadCurve(to: CGPoint(x: 372, y: 206), control: CGPoint(x: 317, y: 186))
ctx.strokePath()
ctx.setLineDash(phase: 0, lengths: [])
ctx.move(to: CGPoint(x: 364, y: 197))
ctx.addLine(to: CGPoint(x: 376, y: 207))
ctx.addLine(to: CGPoint(x: 363, y: 215))
ctx.strokePath()

text("First time it opens, if macOS says it can't check the app:", y: 352, size: 11, weight: .regular, color: NSColor(srgbRed: 0.5, green: 0.5, blue: 0.52, alpha: 1))
text("System Settings  ›  Privacy & Security  ›  Open Anyway", y: 369, size: 11, weight: .medium, color: NSColor(srgbRed: 0.38, green: 0.38, blue: 0.4, alpha: 1))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))

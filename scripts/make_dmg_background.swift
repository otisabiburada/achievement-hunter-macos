// Renders the DMG installer background: usage `swift make_dmg_background.swift <out.png> <scale>`
// Logical size is 660x400 points; scale 2 gives the Retina rendition.
import AppKit

let out = CommandLine.arguments[1]
let scale = CGFloat(Double(CommandLine.arguments[2]) ?? 1)
let W: CGFloat = 660, H: CGFloat = 400
// Icon centres used by build.sh (Finder positions), measured from the top-left of the window content.
let appX: CGFloat = 170, appsX: CGFloat = 490, iconY: CGFloat = 205

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)   // points; DPI follows from the scale
NSGraphicsContext.saveGraphicsState()
let gc = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gc
let ctx = gc.cgContext
// Flip to top-left origin so coordinates match Finder's.
ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}

// Background gradient (matches the app icon's navy)
let space = CGColorSpaceCreateDeviceRGB()
let grad = CGGradient(colorsSpace: space, colors: [color(0x0B1230).cgColor, color(0x1B2C63).cgColor] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: W, y: H), options: [])

// Soft glows behind each icon
for x in [appX, appsX] {
    let glow = CGGradient(colorsSpace: space, colors: [color(0x1E9BFF, 0.28).cgColor, color(0x1E9BFF, 0).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: x, y: iconY - 8), startRadius: 0, endCenter: CGPoint(x: x, y: iconY - 8), endRadius: 120, options: [])
}

// Sparkles
var seed: UInt64 = 7
func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat((seed >> 33) % 10000) / 10000 }
for _ in 0..<26 {
    let x = rnd() * W, y = rnd() * H, r = 0.8 + rnd() * 1.6
    ctx.setFillColor(color(0xFFFFFF, 0.10 + rnd() * 0.25).cgColor)
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}

func text(_ s: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, y: CGFloat, hex: UInt32 = 0xFFFFFF) {
    let para = NSMutableParagraphStyle(); para.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color(hex, alpha),
        .paragraphStyle: para
    ]
    let str = NSAttributedString(string: s, attributes: attrs)
    // NSAttributedString draws upright in a flipped context when we flip the text matrix back.
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    str.draw(in: CGRect(x: 0, y: y, width: W, height: size * 1.6))
}

text("Achievement Hunter", size: 28, weight: .bold, alpha: 1, y: 34)
text("Drag the app into your Applications folder", size: 14, weight: .medium, alpha: 0.72, y: 76)

// Arrow between the two icons
let ay = iconY - 8
ctx.setStrokeColor(color(0x1E9BFF).cgColor)
ctx.setLineWidth(4)
ctx.setLineCap(.round)
ctx.setLineDash(phase: 0, lengths: [2, 11])
ctx.move(to: CGPoint(x: appX + 100, y: ay)); ctx.addLine(to: CGPoint(x: appsX - 112, y: ay))
ctx.strokePath()
ctx.setLineDash(phase: 0, lengths: [])
ctx.setLineJoin(.round)
ctx.setLineWidth(5)
let tip = CGPoint(x: appsX - 92, y: ay)
ctx.move(to: CGPoint(x: tip.x - 16, y: tip.y - 14)); ctx.addLine(to: tip); ctx.addLine(to: CGPoint(x: tip.x - 16, y: tip.y + 14))
ctx.strokePath()

// First-launch note (the app is signed ad hoc, not notarized)
text("First launch: right-click the app in Applications, then choose Open", size: 12, weight: .regular, alpha: 0.55, y: 352)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))

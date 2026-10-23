import AppKit
import CoreGraphics

func renderMasterIcon(size: CGSize) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()
    
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }
    
    let rect = CGRect(origin: .zero, size: size)
    let cornerRadius = size.width * 0.2237 // Apple macOS squircle proportion
    
    let squircle = CGPath(roundedRect: rect.insetBy(dx: size.width * 0.05, dy: size.height * 0.05),
                          cornerWidth: cornerRadius,
                          cornerHeight: cornerRadius,
                          transform: nil)
    
    // Outer shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size.height * 0.04),
                  blur: size.height * 0.06,
                  color: NSColor.black.withAlphaComponent(0.45).cgColor)
    ctx.addPath(squircle)
    ctx.setFillColor(NSColor(red: 0.06, green: 0.08, blue: 0.12, alpha: 1.0).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    
    // Deep Midnight Sapphire Gradient
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        NSColor(red: 0.12, green: 0.15, blue: 0.24, alpha: 1.0).cgColor,
        NSColor(red: 0.04, green: 0.06, blue: 0.10, alpha: 1.0).cgColor
    ] as CFArray
    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(bgGradient,
                               start: CGPoint(x: size.width * 0.5, y: size.height),
                               end: CGPoint(x: size.width * 0.5, y: 0),
                               options: [])
    }
    
    // Targeting Hunter Crosshair Rings
    ctx.setStrokeColor(NSColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 0.25).cgColor)
    ctx.setLineWidth(size.width * 0.008)
    ctx.strokeEllipse(in: rect.insetBy(dx: size.width * 0.18, dy: size.height * 0.18))
    ctx.strokeEllipse(in: rect.insetBy(dx: size.width * 0.28, dy: size.height * 0.28))
    
    // Crosshair ticks
    ctx.setStrokeColor(NSColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 0.4).cgColor)
    ctx.setLineWidth(size.width * 0.006)
    let cx = size.width * 0.5
    let cy = size.height * 0.5
    ctx.move(to: CGPoint(x: cx, y: size.height * 0.14))
    ctx.addLine(to: CGPoint(x: cx, y: size.height * 0.22))
    ctx.move(to: CGPoint(x: cx, y: size.height * 0.78))
    ctx.addLine(to: CGPoint(x: cx, y: size.height * 0.86))
    ctx.move(to: CGPoint(x: size.width * 0.14, y: cy))
    ctx.addLine(to: CGPoint(x: size.width * 0.22, y: cy))
    ctx.move(to: CGPoint(x: size.width * 0.78, y: cy))
    ctx.addLine(to: CGPoint(x: size.width * 0.86, y: cy))
    ctx.strokePath()
    
    // Golden Trophy Center Icon
    let trophyWidth = size.width * 0.44
    let trophyHeight = size.height * 0.44
    let trophyOriginX = (size.width - trophyWidth) * 0.5
    let trophyOriginY = (size.height - trophyHeight) * 0.52
    
    let config = NSImage.SymbolConfiguration(pointSize: trophyWidth, weight: .bold)
    if let trophyImage = NSImage(systemSymbolName: "trophy.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let trophyRect = NSRect(x: trophyOriginX, y: trophyOriginY, width: trophyWidth, height: trophyHeight)
        
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 0),
                      blur: size.width * 0.1,
                      color: NSColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 0.7).cgColor)
        trophyImage.draw(in: trophyRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        ctx.restoreGState()
    }
    
    // Glowing hunter diamond crown star
    let crownConfig = NSImage.SymbolConfiguration(pointSize: size.width * 0.12, weight: .bold)
    if let crown = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?.withSymbolConfiguration(crownConfig) {
        let crownRect = NSRect(x: size.width * 0.64, y: size.height * 0.66, width: size.width * 0.16, height: size.height * 0.16)
        crown.draw(in: crownRect, from: .zero, operation: .sourceOver, fraction: 0.95)
    }
    
    // Rim highlight
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.25).cgColor)
    ctx.setLineWidth(size.width * 0.006)
    ctx.addPath(squircle)
    ctx.strokePath()
    
    ctx.restoreGState()
    image.unlockFocus()
    return image
}

func savePNG(image: NSImage, targetSize: Int, destinationURL: URL) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: targetSize,
                               pixelsHigh: targetSize,
                               bitsPerSample: 8,
                               samplesPerPixel: 4,
                               hasAlpha: true,
                               isPlanar: false,
                               colorSpaceName: .deviceRGB,
                               bytesPerRow: 0,
                               bitsPerPixel: 0)!
    
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: targetSize, height: targetSize),
               from: .zero,
               operation: .copy,
               fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
    
    if let data = rep.representation(using: .png, properties: [:]) {
        try data.write(to: destinationURL)
    }
}

let fileManager = FileManager.default
let baseDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconsetDir = baseDir.appendingPathComponent("Resources/AppIcon.iconset")
try? fileManager.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let masterImage = renderMasterIcon(size: CGSize(width: 1024, height: 1024))

let iconSizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (filename, size) in iconSizes {
    let fileUrl = iconsetDir.appendingPathComponent(filename)
    try savePNG(image: masterImage, targetSize: size, destinationURL: fileUrl)
}

print("Generated Achievement Hunter iconset at \(iconsetDir.path)")

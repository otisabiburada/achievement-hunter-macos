// Builds Resources/AppIcon.iconset from a source PNG using the standard macOS icon grid:
// on a 1024 canvas the icon body is 824 x 824 (about 80%), centred, with a soft drop shadow.
// Usage: swift make_icon.swift <source.png> <out.iconset dir>
import AppKit
import CoreImage

let src = CommandLine.arguments[1], outDir = CommandLine.arguments[2]
guard let input = CIImage(contentsOf: URL(fileURLWithPath: src)) else { fatalError("cannot read image") }
let ci = CIContext()
let space = CGColorSpaceCreateDeviceRGB()
let bodyRatio: CGFloat = 824.0 / 1024.0

let sizes: [(String, Int)] = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                              ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)]
for (name, px) in sizes {
    let body = max(1, Int((CGFloat(px) * bodyRatio).rounded()))
    let f = CIFilter(name: "CILanczosScaleTransform")!
    f.setValue(input, forKey: kCIInputImageKey)
    f.setValue(CGFloat(body) / input.extent.width, forKey: kCIInputScaleKey)
    f.setValue(1.0, forKey: kCIInputAspectRatioKey)
    let bodyImage = ci.createCGImage(f.outputImage!, from: CGRect(x: 0, y: 0, width: body, height: body))!
    
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let origin = CGFloat(px - body) / 2
    if px >= 64 {
        let k = CGFloat(px) / 1024
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 22 * k, color: CGColor(gray: 0, alpha: 0.38))
    }
    ctx.draw(bodyImage, in: CGRect(x: origin, y: origin, width: CGFloat(body), height: CGFloat(body)))
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/icon_\(name).png"))
}

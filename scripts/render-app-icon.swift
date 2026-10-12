// Run from the repository root: swift scripts/render-app-icon.swift
// Opaque square assets; iOS applies its own corner mask.
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
func color(_ hex: UInt32) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [CGFloat((hex >> 16) & 255) / 255,
        CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255, 1])!
}
func render(background: UInt32, size: Int, destination: String, masked: Bool = false) throws {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setAllowsAntialiasing(true)
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    context.translateBy(x: 0, y: 1024)
    context.scaleBy(x: 1, y: -1)
    if masked {
        context.setFillColor(color(0xF5F6F2))
        context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 1024, height: 1024),
                               cornerWidth: 224, cornerHeight: 224, transform: nil))
        context.clip()
    }
    context.setFillColor(color(background))
    context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))

    // Three treads form one continuous, soft ascending stride.
    let steps = CGMutablePath()
    steps.move(to: CGPoint(x: 268, y: 728))
    steps.addLine(to: CGPoint(x: 430, y: 728))
    steps.addLine(to: CGPoint(x: 430, y: 566))
    steps.addLine(to: CGPoint(x: 592, y: 566))
    steps.addLine(to: CGPoint(x: 592, y: 404))
    steps.addLine(to: CGPoint(x: 754, y: 404))
    context.setStrokeColor(color(0xF3F0DD))
    context.setLineWidth(108)
    context.setLineJoin(.round)
    context.setLineCap(.round)
    context.addPath(steps)
    context.strokePath()

    let stem = CGMutablePath()
    stem.move(to: CGPoint(x: 702, y: 404))
    stem.addCurve(to: CGPoint(x: 678, y: 284), control1: CGPoint(x: 704, y: 348), control2: CGPoint(x: 697, y: 316))
    context.setLineWidth(32)
    context.addPath(stem)
    context.strokePath()

    // A single warm seed leaf: progress is growth, rather than a score.
    let leaf = CGMutablePath()
    leaf.move(to: CGPoint(x: 688, y: 306))
    leaf.addCurve(to: CGPoint(x: 576, y: 174), control1: CGPoint(x: 599, y: 318), control2: CGPoint(x: 565, y: 244))
    leaf.addCurve(to: CGPoint(x: 688, y: 306), control1: CGPoint(x: 670, y: 164), control2: CGPoint(x: 728, y: 223))
    leaf.closeSubpath()
    context.setFillColor(color(0xE8BA65))
    context.addPath(leaf)
    context.fillPath()

    let url = root.appendingPathComponent(destination)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let image = context.makeImage()!
    let bitmap = NSBitmapImageRep(cgImage: image)
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}
try render(background: 0x245849, size: 1024, destination: "LittleStride/Resources/Assets.xcassets/AppIcon.appiconset/Icon.png")
try render(background: 0x14392F, size: 1024, destination: "LittleStride/Resources/Assets.xcassets/AppIcon.appiconset/Icon-dark.png")
try render(background: 0x245849, size: 256, destination: "LittleStride/Resources/Assets.xcassets/BrandMark.imageset/BrandMark.png")
try render(background: 0x245849, size: 128, destination: "prototype/brand-mark.png")
try render(background: 0x245849, size: 512, destination: "docs/design/brand/图标预览.png", masked: true)

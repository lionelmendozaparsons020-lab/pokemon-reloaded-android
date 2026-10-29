// Render the repository's Android vector launcher icon with CoreGraphics.
// Geometry/colors match res/drawable/ic_launcher_{background,foreground}.xml.
import AppKit
let directory = CommandLine.arguments[1]
for size in [120, 152, 167, 180, 1024] {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: size * 4, space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.scaleBy(x: CGFloat(size) / 108, y: CGFloat(size) / 108)
    let colors = [0x5A5A5A, 0x3C3C3C, 0x232323].map { n in
        CGColor(red: CGFloat((n >> 16) & 255) / 255, green: CGFloat((n >> 8) & 255) / 255,
                blue: CGFloat(n & 255) / 255, alpha: 1)
    }
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0, 0.5, 1])!
    context.drawRadialGradient(gradient, startCenter: CGPoint(x: 54, y: 54), startRadius: 0,
                              endCenter: CGPoint(x: 54, y: 54), endRadius: 86, options: .drawsAfterEndLocation)
    func color(_ n: Int) -> CGColor { CGColor(red: CGFloat((n >> 16) & 255) / 255,
        green: CGFloat((n >> 8) & 255) / 255, blue: CGFloat(n & 255) / 255, alpha: 1) }
    func circle(_ radius: CGFloat) -> CGRect { CGRect(x: 54-radius, y: 54-radius, width: radius*2, height: radius*2) }
    context.setStrokeColor(color(0x9E9E9E)); context.setLineWidth(1.6); context.strokeEllipse(in: circle(28.4))
    context.setFillColor(color(0xF1F1F1)); context.fillEllipse(in: circle(25.4))
    context.saveGState(); context.clip(to: CGRect(x: 0, y: 54, width: 108, height: 54))
    context.setFillColor(color(0xF26A1B)); context.fillEllipse(in: circle(25.4)); context.restoreGState()
    context.setFillColor(color(0x1C1C1C)); context.fill(CGRect(x: 28.6, y: 50.8, width: 50.8, height: 6.4)); context.fillEllipse(in: circle(7.6))
    context.setFillColor(color(0xF1F1F1)); context.fillEllipse(in: circle(3.6))
    let image = NSBitmapImageRep(cgImage: context.makeImage()!)
    try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory).appendingPathComponent("Icon\(size).png"))
}

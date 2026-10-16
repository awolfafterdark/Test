import AppKit
import Foundation

// Run on macOS before XcodeGen. An optional JPEG is center-cropped to a square.
// App Store icon slots are generated as opaque PNGs in an asset catalog.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let catalog = root.appendingPathComponent("PatcherApp/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: true)

let source: NSImage?
if CommandLine.arguments.count > 1 {
    guard let image = NSImage(contentsOfFile: CommandLine.arguments[1]),
          image.size.width > 0, image.size.height > 0 else {
        fputs("Could not decode the supplied JPEG.\n", stderr)
        exit(2)
    }
    source = image
} else {
    source = nil
}

func iconPNG(_ dimension: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: dimension,
                                       pixelsHigh: dimension, bitsPerSample: 8,
                                       samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "PickerPatcherIcon", code: 1)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let rect = NSRect(x: 0, y: 0, width: dimension, height: dimension)
    if let source = source {
        NSColor.black.setFill()
        rect.fill()
        let side = min(source.size.width, source.size.height)
        let crop = NSRect(x: (source.size.width - side) / 2,
                          y: (source.size.height - side) / 2,
                          width: side, height: side)
        source.draw(in: rect, from: crop, operation: .copy, fraction: 1)
    } else {
        NSColor(calibratedRed: 0.14, green: 0.34, blue: 0.64, alpha: 1).setFill()
        rect.fill()
        let margin = CGFloat(dimension) * 0.21
        let frame = NSBezierPath(roundedRect: rect.insetBy(dx: margin, dy: margin),
                                 xRadius: CGFloat(dimension) * 0.09,
                                 yRadius: CGFloat(dimension) * 0.09)
        frame.lineWidth = CGFloat(dimension) * 0.055
        NSColor.white.setStroke()
        frame.stroke()
        let sun = NSBezierPath(ovalIn: NSRect(x: CGFloat(dimension) * 0.58,
                                           y: CGFloat(dimension) * 0.55,
                                           width: CGFloat(dimension) * 0.105,
                                           height: CGFloat(dimension) * 0.105))
        NSColor.white.setFill()
        sun.fill()
        let hills = NSBezierPath()
        hills.move(to: NSPoint(x: CGFloat(dimension) * 0.24, y: CGFloat(dimension) * 0.34))
        hills.line(to: NSPoint(x: CGFloat(dimension) * 0.43, y: CGFloat(dimension) * 0.54))
        hills.line(to: NSPoint(x: CGFloat(dimension) * 0.56, y: CGFloat(dimension) * 0.41))
        hills.line(to: NSPoint(x: CGFloat(dimension) * 0.67, y: CGFloat(dimension) * 0.52))
        hills.lineWidth = CGFloat(dimension) * 0.048
        hills.lineCapStyle = .round
        hills.lineJoinStyle = .round
        hills.stroke()
    }
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "PickerPatcherIcon", code: 2)
    }
    return png
}

let slots: [(String, String, Int, Int)] = [
    ("iphone", "20x20", 2, 40), ("iphone", "20x20", 3, 60),
    ("iphone", "29x29", 2, 58), ("iphone", "29x29", 3, 87),
    ("iphone", "40x40", 2, 80), ("iphone", "40x40", 3, 120),
    ("iphone", "60x60", 2, 120), ("iphone", "60x60", 3, 180),
    ("ipad", "20x20", 1, 20), ("ipad", "20x20", 2, 40),
    ("ipad", "29x29", 1, 29), ("ipad", "29x29", 2, 58),
    ("ipad", "40x40", 1, 40), ("ipad", "40x40", 2, 80),
    ("ipad", "76x76", 1, 76), ("ipad", "76x76", 2, 152),
    ("ipad", "83.5x83.5", 2, 167),
    ("ios-marketing", "1024x1024", 1, 1024)
]
var images: [[String: String]] = []
for (idiom, size, scale, pixels) in slots {
    let file = "Icon-\(idiom)-\(size)-\(scale)x.png"
    try iconPNG(pixels).write(to: catalog.appendingPathComponent(file))
    images.append(["filename": file, "idiom": idiom, "size": size, "scale": "\(scale)x"])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: catalog.appendingPathComponent("Contents.json"))
print("Generated \(images.count) opaque app icon slots")

import AppKit
import Foundation

// Reproducible size exports of the approved artwork; never redraw the icon.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = root.appendingPathComponent("Design/AppIcon/Folisona-master.png")
guard let image = NSImage(contentsOf: source) else { fatalError("Missing \(source.path)") }
let output = root.appendingPathComponent("Release/Icons")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let sizes = [20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024]
for size in sizes {
    var sourceRect = CGRect(origin: .zero, size: image.size)
    guard let original = image.cgImage(forProposedRect: &sourceRect, context: nil, hints: nil),
          let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        fatalError("Cannot create RGB icon context")
    }
    context.interpolationQuality = .high
    context.draw(original, in: CGRect(x: 0, y: 0, width: size, height: size))
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: output.appendingPathComponent("Folisona-\(size).png"), options: .atomic)
    if size == 1024 {
        try data.write(to: root.appendingPathComponent("Folisona/Assets.xcassets/AppIcon.appiconset/AppIcon.png"), options: .atomic)
    }
}
print("Exported \(sizes.count) opaque icon sizes and updated AppIcon (1024 px).")

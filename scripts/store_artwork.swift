import AppKit
import Foundation

// Layout real simulator captures without changing the app UI shown inside them.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255)/255, green: CGFloat((hex >> 8) & 255)/255,
            blue: CGFloat(hex & 255)/255, alpha: 1)
}
let forest = color(0x003D2B), paper = color(0xF7F1E3)
let copy: [String: [(String, String)]] = [
    "es": [("Tus libros.\nUna nueva voz.", "GRATIS · SIN PUBLICIDAD"),
           ("Una historia.\nCapítulo a capítulo.", "EPUB · PDF · TXT · MARKDOWN"),
           ("¿Te dormiste?\nEncuentra dónde seguir.", "CONSULTA LAS HORAS DE ESCUCHA")],
    "en": [("Your books.\nA new voice.", "FREE · NO ADS"),
           ("Your story.\nChapter by chapter.", "EPUB · PDF · TXT · MARKDOWN"),
           ("Drifted off?\nFind your place again.", "LOOK BACK AT LISTENING TIMES")]
]
let screens = ["01-library", "02-chapters", "03-reader"]
for locale in ["es", "en"] {
    for family in ["iphone", "iphone-max", "iphone-air", "iphone-17e", "ipad", "duo"] {
        for (index, name) in screens.enumerated() {
            let input = root.appendingPathComponent("Release/Screenshots/\(locale)/\(family)/\(name).jpg")
            guard let screenshot = NSImage(contentsOf: input) else { fatalError("Missing capture: \(input)") }
            let rep = screenshot.representations[0]
            let w = CGFloat(rep.pixelsWide), h = CGFloat(rep.pixelsHigh)
            let context = CGContext(data: nil, width: Int(w), height: Int(h), bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            forest.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
            let unit = min(w/1206, h/2400)
            func text(_ value: String, y: CGFloat, size: CGFloat, bold: Bool = false, serif: Bool = false) {
                let style = NSMutableParagraphStyle(); style.alignment = .center
                let base = NSFont.systemFont(ofSize: size * unit, weight: bold ? .semibold : .regular)
                let font = serif ? NSFont(descriptor: base.fontDescriptor.withDesign(.serif)!, size: size * unit)! : base
                (value as NSString).draw(in: NSRect(x: w*0.035, y: y, width: w*0.93, height: size*unit*2.65),
                    withAttributes: [.font: font, .foregroundColor: paper, .paragraphStyle: style])
            }
            text("Folisona", y: h - 150*unit, size: 36, bold: true)
            text(copy[locale]![index].0, y: h - 365*unit, size: 72, serif: true)
            text(copy[locale]![index].1, y: h - 427*unit, size: 25, bold: true)
            let top = h - 475*unit
            let scale = min(w*0.86/w, (top-70*unit)/h)
            let frame = NSRect(x: (w-w*scale)/2, y: 70*unit, width: w*scale, height: h*scale)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
            shadow.shadowBlurRadius = 35*unit; shadow.shadowOffset = NSSize(width: 0, height: -16*unit); shadow.set()
            paper.setFill(); NSBezierPath(roundedRect: frame.insetBy(dx: -6*unit, dy: -6*unit), xRadius: 34*unit, yRadius: 34*unit).fill()
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: frame, xRadius: 28*unit, yRadius: 28*unit).addClip()
            screenshot.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.restoreGraphicsState()
            let dir = root.appendingPathComponent("Release/StoreScreenshots/\(locale)/\(family)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
            try bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.95])!.write(to: dir.appendingPathComponent(name+".jpg"))
        }
    }
}
print("36 branded screenshots generated in Release/StoreScreenshots")

// Generates Support/AppIcon.iconset PNGs (run `iconutil -c icns` after).
// Usage: swift Support/make-icon.swift   (from the repo root)
import AppKit

let variants: [(pixels: Int, name: String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"),
    (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"),
    (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]

let iconsetURL = URL(fileURLWithPath: "Support/AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func render(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    let s = CGFloat(pixels)

    // Rounded-square background, brand orange gradient.
    let inset = s * 0.045
    let bgRect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = NSBezierPath(roundedRect: bgRect, xRadius: s * 0.21, yRadius: s * 0.21)
    NSGradient(
        starting: NSColor(calibratedRed: 1.00, green: 0.64, blue: 0.26, alpha: 1),
        ending: NSColor(calibratedRed: 0.92, green: 0.32, blue: 0.12, alpha: 1)
    )!.draw(in: bg, angle: -70)

    // White hare, slightly above center.
    if let hare = NSImage(systemSymbolName: "hare.fill", accessibilityDescription: nil),
       let sym = hare.withSymbolConfiguration(.init(pointSize: s * 0.40, weight: .semibold)) {
        let tinted = NSImage(size: sym.size, flipped: false) { rect in
            sym.draw(in: rect)
            NSColor.white.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        let aspect = sym.size.height / max(sym.size.width, 1)
        let width = s * 0.56
        let height = width * aspect
        tinted.draw(in: NSRect(
            x: (s - width) / 2,
            y: s * 0.34,
            width: width,
            height: height
        ))
    }

    // The reading-guide underline.
    let bar = NSRect(x: s * 0.28, y: s * 0.20, width: s * 0.44, height: s * 0.05)
    NSColor.white.withAlphaComponent(0.92).setFill()
    NSBezierPath(roundedRect: bar, xRadius: bar.height / 2, yRadius: bar.height / 2).fill()

    return rep
}

for variant in variants {
    let rep = render(pixels: variant.pixels)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: iconsetURL.appendingPathComponent("\(variant.name).png"))
}
print("Wrote \(variants.count) images to \(iconsetURL.path)")

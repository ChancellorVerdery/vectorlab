// Generates Resources/AppIcon.icns — three colored arrows on a dark tile.
// Run from the repo root:  swift scripts/make-icon.swift && iconutil -c icns AppIcon.iconset -o Resources/AppIcon.icns
import AppKit

func draw(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    defer { NSGraphicsContext.restoreGraphicsState() }

    let s = CGFloat(px)
    let inset = s * 0.05
    let tile = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    NSColor(red: 0.075, green: 0.085, blue: 0.13, alpha: 1).setFill()
    NSBezierPath(roundedRect: tile, xRadius: s * 0.2, yRadius: s * 0.2).fill()

    func arrow(_ angleDeg: CGFloat, _ len: CGFloat, _ color: NSColor) {
        let c = CGPoint(x: s * 0.30, y: s * 0.28)
        let a = angleDeg * .pi / 180
        let tip = CGPoint(x: c.x + cos(a) * len, y: c.y + sin(a) * len)
        color.setStroke()
        let line = NSBezierPath()
        line.move(to: c)
        line.line(to: tip)
        line.lineWidth = s * 0.05
        line.lineCapStyle = .round
        line.stroke()
        let head = NSBezierPath()
        let hl = s * 0.11
        head.move(to: CGPoint(x: tip.x - cos(a - 0.45) * hl, y: tip.y - sin(a - 0.45) * hl))
        head.line(to: tip)
        head.line(to: CGPoint(x: tip.x - cos(a + 0.45) * hl, y: tip.y - sin(a + 0.45) * hl))
        head.lineWidth = s * 0.05
        head.lineCapStyle = .round
        head.lineJoinStyle = .round
        head.stroke()
    }
    arrow(12, s * 0.52, .systemBlue)
    arrow(52, s * 0.46, .systemRed)
    arrow(92, s * 0.40, .systemGreen)
    return rep
}

let dir = "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let rep = draw(size * scale)
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        try! rep.representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: "\(dir)/\(name)"))
    }
}
print("wrote \(dir)")

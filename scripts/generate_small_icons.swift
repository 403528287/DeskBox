import AppKit

func makeBitmap(_ size: Int) -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("bitmap")
    }
    return rep
}

func save(_ rep: NSBitmapImageRep, to path: String) {
    guard let data = rep.representation(
        using: .png,
        properties: [:]
    ) else {
        fatalError("png")
    }
    try! data.write(to: URL(fileURLWithPath: path))
}

func drawBase(size: CGFloat, radius: CGFloat) -> NSBezierPath {
    let inset = max(0.5, size * 0.035)
    let rect = NSRect(
        x: inset,
        y: inset,
        width: size - inset * 2,
        height: size - inset * 2
    )
    let path = NSBezierPath(
        roundedRect: rect,
        xRadius: radius,
        yRadius: radius
    )

    path.addClip()

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.10, green: 0.45, blue: 0.98, alpha: 1),
        NSColor(calibratedRed: 0.48, green: 0.46, blue: 0.98, alpha: 1),
        NSColor(calibratedRed: 0.92, green: 0.68, blue: 0.86, alpha: 1)
    ])!
    gradient.draw(in: rect, angle: -38)

    NSColor.white.withAlphaComponent(0.16).setFill()
    NSBezierPath(
        roundedRect: NSRect(
            x: rect.minX + size * 0.05,
            y: rect.midY + size * 0.04,
            width: rect.width * 0.78,
            height: rect.height * 0.34
        ),
        xRadius: radius * 0.75,
        yRadius: radius * 0.75
    ).fill()

    return path
}

func render64(path: String) {
    let size = 64
    let rep = makeBitmap(size)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    _ = drawBase(size: 64, radius: 14)

    let folder = NSBezierPath(
        roundedRect: NSRect(x: 14, y: 16, width: 33, height: 28),
        xRadius: 6,
        yRadius: 6
    )
    NSGradient(colors: [
        NSColor(calibratedRed: 0.02, green: 0.65, blue: 1.0, alpha: 1),
        NSColor(calibratedRed: 0.02, green: 0.32, blue: 0.96, alpha: 1)
    ])!.draw(in: folder, angle: -25)

    let tab = NSBezierPath(
        roundedRect: NSRect(x: 18, y: 40, width: 16, height: 8),
        xRadius: 3.5,
        yRadius: 3.5
    )
    NSColor(calibratedRed: 0.05, green: 0.52, blue: 0.98, alpha: 1).setFill()
    tab.fill()

    let note = NSBezierPath(
        roundedRect: NSRect(x: 34, y: 14, width: 18, height: 25),
        xRadius: 4,
        yRadius: 4
    )
    NSGradient(colors: [
        NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.50, alpha: 1),
        NSColor(calibratedRed: 1.0, green: 0.65, blue: 0.28, alpha: 1)
    ])!.draw(in: note, angle: -35)

    NSColor.white.withAlphaComponent(0.62).setStroke()
    let outline = NSBezierPath(
        roundedRect: NSRect(x: 1.3, y: 1.3, width: 61.4, height: 61.4),
        xRadius: 13.3,
        yRadius: 13.3
    )
    outline.lineWidth = 1
    outline.stroke()

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    save(rep, to: path)
}

func render32(path: String) {
    let size = 32
    let rep = makeBitmap(size)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    _ = drawBase(size: 32, radius: 7)

    let blue = NSBezierPath(
        roundedRect: NSRect(x: 7, y: 8, width: 16, height: 15),
        xRadius: 3.5,
        yRadius: 3.5
    )
    NSColor(calibratedRed: 0.02, green: 0.52, blue: 1.0, alpha: 1).setFill()
    blue.fill()

    let tab = NSBezierPath(
        roundedRect: NSRect(x: 9, y: 20, width: 8, height: 4),
        xRadius: 1.8,
        yRadius: 1.8
    )
    NSColor(calibratedRed: 0.03, green: 0.42, blue: 0.98, alpha: 1).setFill()
    tab.fill()

    let yellow = NSBezierPath(
        roundedRect: NSRect(x: 17, y: 7, width: 9, height: 13),
        xRadius: 2.3,
        yRadius: 2.3
    )
    NSColor(calibratedRed: 1.0, green: 0.75, blue: 0.31, alpha: 1).setFill()
    yellow.fill()

    NSColor.white.withAlphaComponent(0.70).setStroke()
    let outline = NSBezierPath(
        roundedRect: NSRect(x: 0.75, y: 0.75, width: 30.5, height: 30.5),
        xRadius: 6.6,
        yRadius: 6.6
    )
    outline.lineWidth = 0.9
    outline.stroke()

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    save(rep, to: path)
}

func render16(path: String) {
    let size = 16
    let rep = makeBitmap(size)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    _ = drawBase(size: 16, radius: 3.5)

    let blue = NSBezierPath(
        roundedRect: NSRect(x: 3, y: 4, width: 8, height: 8),
        xRadius: 2,
        yRadius: 2
    )
    NSColor(calibratedRed: 0.01, green: 0.48, blue: 1.0, alpha: 1).setFill()
    blue.fill()

    let yellow = NSBezierPath(
        roundedRect: NSRect(x: 9, y: 3.5, width: 4.5, height: 6.5),
        xRadius: 1.2,
        yRadius: 1.2
    )
    NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.28, alpha: 1).setFill()
    yellow.fill()

    NSColor.white.withAlphaComponent(0.78).setStroke()
    let outline = NSBezierPath(
        roundedRect: NSRect(x: 0.5, y: 0.5, width: 15, height: 15),
        xRadius: 3.2,
        yRadius: 3.2
    )
    outline.lineWidth = 0.75
    outline.stroke()

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    save(rep, to: path)
}

let root = URL(
    fileURLWithPath: FileManager.default.currentDirectoryPath
)
.appendingPathComponent("DeskBox")
.appendingPathComponent("Assets.xcassets")
.appendingPathComponent("AppIcon.appiconset")
.path
render64(path: root + "/icon_64x64.png")
render32(path: root + "/icon_32x32.png")
render16(path: root + "/icon_16x16.png")
print("SMALL_ICONS_READY")

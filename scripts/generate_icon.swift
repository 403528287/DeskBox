import AppKit

let size = 1024
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

NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
    fatalError("context")
}
NSGraphicsContext.current = context

NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()

let card = NSBezierPath(
    roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896),
    xRadius: 220,
    yRadius: 220
)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowBlurRadius = 50
shadow.shadowOffset = NSSize(width: 0, height: -22)
shadow.set()
NSColor(calibratedRed: 0.22, green: 0.42, blue: 0.90, alpha: 0.96).setFill()
card.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
card.addClip()

let bg = NSGradient(colors: [
    NSColor(calibratedRed: 0.10, green: 0.38, blue: 0.95, alpha: 1),
    NSColor(calibratedRed: 0.34, green: 0.46, blue: 0.98, alpha: 1),
    NSColor(calibratedRed: 0.72, green: 0.56, blue: 0.98, alpha: 1),
    NSColor(calibratedRed: 1.00, green: 0.74, blue: 0.54, alpha: 0.94)
])!
bg.draw(
    in: NSRect(x: 64, y: 64, width: 896, height: 896),
    angle: -38
)

let gloss = NSBezierPath()
gloss.move(to: NSPoint(x: 90, y: 720))
gloss.curve(
    to: NSPoint(x: 760, y: 930),
    controlPoint1: NSPoint(x: 260, y: 980),
    controlPoint2: NSPoint(x: 580, y: 1010)
)
gloss.curve(
    to: NSPoint(x: 930, y: 650),
    controlPoint1: NSPoint(x: 900, y: 880),
    controlPoint2: NSPoint(x: 970, y: 760)
)
gloss.line(to: NSPoint(x: 930, y: 960))
gloss.line(to: NSPoint(x: 90, y: 960))
gloss.close()
NSColor.white.withAlphaComponent(0.11).setFill()
gloss.fill()

NSGraphicsContext.restoreGraphicsState()

NSColor.white.withAlphaComponent(0.50).setStroke()
card.lineWidth = 3
card.stroke()

// Glass cube
let top = NSBezierPath()
top.move(to: NSPoint(x: 278, y: 692))
top.line(to: NSPoint(x: 514, y: 820))
top.line(to: NSPoint(x: 750, y: 692))
top.line(to: NSPoint(x: 514, y: 562))
top.close()

let left = NSBezierPath()
left.move(to: NSPoint(x: 278, y: 692))
left.line(to: NSPoint(x: 514, y: 562))
left.line(to: NSPoint(x: 514, y: 286))
left.line(to: NSPoint(x: 278, y: 420))
left.close()

let right = NSBezierPath()
right.move(to: NSPoint(x: 750, y: 692))
right.line(to: NSPoint(x: 514, y: 562))
right.line(to: NSPoint(x: 514, y: 286))
right.line(to: NSPoint(x: 750, y: 420))
right.close()

NSColor.white.withAlphaComponent(0.13).setFill()
top.fill()
NSColor.white.withAlphaComponent(0.09).setFill()
left.fill()
NSColor.white.withAlphaComponent(0.07).setFill()
right.fill()

for face in [top, left, right] {
    NSColor.white.withAlphaComponent(0.80).setStroke()
    face.lineWidth = 8
    face.lineJoinStyle = .round
    face.stroke()
}

// Folder
NSGraphicsContext.saveGraphicsState()
let folderShadow = NSShadow()
folderShadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
folderShadow.shadowBlurRadius = 24
folderShadow.shadowOffset = NSSize(width: 0, height: -12)
folderShadow.set()

let folderBody = NSBezierPath(
    roundedRect: NSRect(x: 340, y: 360, width: 282, height: 238),
    xRadius: 44,
    yRadius: 44
)
let folderGrad = NSGradient(colors: [
    NSColor(calibratedRed: 0.05, green: 0.62, blue: 1.0, alpha: 1),
    NSColor(calibratedRed: 0.02, green: 0.30, blue: 0.95, alpha: 1)
])!
folderGrad.draw(in: folderBody, angle: -24)

let tab = NSBezierPath(
    roundedRect: NSRect(x: 372, y: 555, width: 142, height: 72),
    xRadius: 28,
    yRadius: 28
)
folderGrad.draw(in: tab, angle: -24)
NSGraphicsContext.restoreGraphicsState()

let folderHighlight = NSBezierPath(
    roundedRect: NSRect(x: 354, y: 376, width: 254, height: 205),
    xRadius: 35,
    yRadius: 35
)
NSColor.white.withAlphaComponent(0.10).setFill()
folderHighlight.fill()

// Note card
NSGraphicsContext.saveGraphicsState()
let noteShadow = NSShadow()
noteShadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
noteShadow.shadowBlurRadius = 26
noteShadow.shadowOffset = NSSize(width: 0, height: -12)
noteShadow.set()

let note = NSBezierPath(
    roundedRect: NSRect(x: 520, y: 316, width: 224, height: 260),
    xRadius: 34,
    yRadius: 34
)
let noteGrad = NSGradient(colors: [
    NSColor(calibratedRed: 1.00, green: 0.88, blue: 0.50, alpha: 1),
    NSColor(calibratedRed: 1.00, green: 0.66, blue: 0.30, alpha: 1)
])!
noteGrad.draw(in: note, angle: -35)
NSGraphicsContext.restoreGraphicsState()

let lineColor = NSColor(calibratedRed: 0.92, green: 0.42, blue: 0.20, alpha: 0.45)
lineColor.setStroke()
for (i, width) in [128, 150, 112].enumerated() {
    let y = CGFloat(490 - i * 46)
    let p = NSBezierPath()
    p.move(to: NSPoint(x: 558, y: y))
    p.line(to: NSPoint(x: 558 + CGFloat(width), y: y))
    p.lineWidth = 12
    p.lineCapStyle = .round
    p.stroke()
}

// Fine glass highlight
let cubeHighlight = NSBezierPath()
cubeHighlight.move(to: NSPoint(x: 292, y: 696))
cubeHighlight.line(to: NSPoint(x: 514, y: 814))
cubeHighlight.lineWidth = 4
cubeHighlight.lineCapStyle = .round
NSColor.white.withAlphaComponent(0.95).setStroke()
cubeHighlight.stroke()

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    fatalError("png")
}

let output = URL(
    fileURLWithPath: FileManager.default.currentDirectoryPath
)
.appendingPathComponent("DeskBox")
.appendingPathComponent("DeskBoxIcon1024.png")
try data.write(to: output)
print(output.path)

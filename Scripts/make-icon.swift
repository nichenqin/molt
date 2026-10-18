import AppKit
import Foundation

// Draws Molt's 1024pt master icon. Feather = shed the old version.
let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let rect = NSRect(x: 72, y: 72, width: 880, height: 880)
let background = NSBezierPath(roundedRect: rect, xRadius: 196, yRadius: 196)

let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.07, green: 0.27, blue: 0.26, alpha: 1),
    NSColor(calibratedRed: 0.035, green: 0.08, blue: 0.11, alpha: 1),
    NSColor(calibratedRed: 0.02, green: 0.035, blue: 0.05, alpha: 1),
])!
gradient.draw(in: background, angle: -65)

// Soft mint glow behind the feather.
let glow = NSBezierPath(ovalIn: NSRect(x: 250, y: 250, width: 560, height: 560))
NSColor(calibratedRed: 0.35, green: 0.95, blue: 0.78, alpha: 0.10).setFill()
glow.fill()

// Feather silhouette, rotated.
let feather = NSBezierPath()
feather.move(to: NSPoint(x: 0, y: -330))
feather.curve(
    to: NSPoint(x: 0, y: 330),
    controlPoint1: NSPoint(x: 178, y: -100),
    controlPoint2: NSPoint(x: 158, y: 205)
)
feather.curve(
    to: NSPoint(x: 0, y: -330),
    controlPoint1: NSPoint(x: -158, y: 205),
    controlPoint2: NSPoint(x: -178, y: -100)
)
feather.close()

var transform = AffineTransform()
transform.translate(x: 520, y: 510)
transform.rotate(byDegrees: 39)
feather.transform(using: transform)

NSColor(calibratedRed: 0.96, green: 0.92, blue: 0.84, alpha: 1).setFill()
feather.fill()

// Barbs: thin cuts in the background color.
NSGraphicsContext.current?.saveGraphicsState()
feather.addClip()
let cutColor = NSColor(calibratedRed: 0.035, green: 0.12, blue: 0.13, alpha: 0.42)
cutColor.setStroke()
for index in 0..<9 {
    let y = -250.0 + Double(index) * 62.0
    let curve = NSBezierPath()
    curve.lineWidth = 9
    curve.move(to: NSPoint(x: 0, y: y))
    curve.curve(
        to: NSPoint(x: 150, y: y + 54),
        controlPoint1: NSPoint(x: 64, y: y + 2),
        controlPoint2: NSPoint(x: 118, y: y + 22)
    )
    curve.transform(using: transform)
    curve.stroke()

    let left = NSBezierPath()
    left.lineWidth = 9
    left.move(to: NSPoint(x: 0, y: y + 14))
    left.curve(
        to: NSPoint(x: -142, y: y + 64),
        controlPoint1: NSPoint(x: -58, y: y + 20),
        controlPoint2: NSPoint(x: -112, y: y + 38)
    )
    left.transform(using: transform)
    left.stroke()
}
NSGraphicsContext.current?.restoreGraphicsState()

// Shaft.
let shaft = NSBezierPath()
shaft.lineWidth = 17
shaft.lineCapStyle = .round
shaft.move(to: NSPoint(x: 286, y: 720))
shaft.curve(
    to: NSPoint(x: 764, y: 320),
    controlPoint1: NSPoint(x: 450, y: 600),
    controlPoint2: NSPoint(x: 640, y: 470)
)
NSColor(calibratedRed: 0.12, green: 0.56, blue: 0.48, alpha: 0.95).setStroke()
shaft.stroke()

// A tiny mint spark at the tip.
let spark = NSBezierPath(ovalIn: NSRect(x: 748, y: 302, width: 34, height: 34))
NSColor(calibratedRed: 0.42, green: 0.98, blue: 0.81, alpha: 1).setFill()
spark.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Could not render icon")
}

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon-1024.png")
try png.write(to: output)
print(output.path)

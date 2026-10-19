import AppKit
import Foundation

let width = 1200.0
let height = 630.0
let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()

let background = NSGradient(colors: [
    NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.08, alpha: 1),
    NSColor(calibratedRed: 0.03, green: 0.03, blue: 0.04, alpha: 1),
])!
background.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -55)

let glow = NSBezierPath(ovalIn: NSRect(x: 720, y: -160, width: 720, height: 720))
NSColor(calibratedRed: 0.15, green: 0.39, blue: 0.92, alpha: 0.20).setFill()
glow.fill()

if let icon = NSImage(contentsOfFile: "Resources/build/icon-1024.png") {
    icon.draw(in: NSRect(x: 84, y: 380, width: 150, height: 150))
}

func draw(_ text: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    (text as NSString).draw(at: point, withAttributes: attributes)
}

draw("Remige", at: NSPoint(x: 84, y: 268), size: 116, weight: .bold, color: .white)
draw("Every update. One place.", at: NSPoint(x: 88, y: 205), size: 46, weight: .medium, color: NSColor(calibratedWhite: 0.93, alpha: 1))
draw(
    "Homebrew  ·  npm  ·  Bun  ·  DMG apps  ·  App Store  ·  curl tools",
    at: NSPoint(x: 90, y: 150),
    size: 22,
    weight: .regular,
    color: NSColor(calibratedRed: 0.48, green: 0.64, blue: 1.0, alpha: 1)
)
draw("Native macOS 14+  ·  Universal binary  ·  MIT", at: NSPoint(x: 90, y: 76), size: 20, weight: .regular, color: NSColor(calibratedWhite: 0.62, alpha: 1))
draw("github.com/nichenqin/remige", at: NSPoint(x: 850, y: 76), size: 20, weight: .medium, color: NSColor(calibratedWhite: 0.74, alpha: 1))

// A few update rows as a visual motif.
let rows: [(String, String, Bool)] = [
    ("cc-switch", "4.0.14 → 4.0.15", true),
    ("npm", "11.20.0 → 12.2.0", true),
    ("IINA", "1.4.4 → 1.5.0", false),
]
var y = 470.0
for (name, version, oneClick) in rows {
    let card = NSBezierPath(roundedRect: NSRect(x: 690, y: y, width: 420, height: 54), xRadius: 12, yRadius: 12)
    NSColor(calibratedWhite: 1, alpha: 0.07).setFill()
    card.fill()
    draw(name, at: NSPoint(x: 708, y: y + 16), size: 18, weight: .medium, color: .white)
    draw(version, at: NSPoint(x: 812, y: y + 17), size: 16, weight: .regular, color: NSColor(calibratedWhite: 0.72, alpha: 1))
    let dot = NSBezierPath(ovalIn: NSRect(x: 1072, y: y + 21, width: 12, height: 12))
    (oneClick
        ? NSColor(calibratedRed: 0.48, green: 0.64, blue: 1.0, alpha: 1)
        : NSColor(calibratedRed: 0.48, green: 0.49, blue: 0.54, alpha: 1)).setFill()
    dot.fill()
    y -= 68
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Could not render")
}
let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "site/assets/og.png")
try png.write(to: output)
print(output.path)

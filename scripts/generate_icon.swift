import AppKit
import CoreGraphics
import UniformTypeIdentifiers

func generateIcon(size: CGFloat, outputPath: String) {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return
    }

    let scale = size / 1024.0

    // Background Container (macOS Squircle)
    let margin: CGFloat = 64 * scale
    let rectSize: CGFloat = size - margin * 2
    let cornerRadius: CGFloat = 200 * scale
    let outerRect = NSRect(x: margin, y: margin, width: rectSize, height: rectSize)
    let outerPath = NSBezierPath(roundedRect: outerRect, xRadius: cornerRadius, yRadius: cornerRadius)

    // Base Gradient: Deep Space Obsidian to Electric Indigo
    let gradient = NSGradient(
        colors: [
            NSColor(red: 0.08, green: 0.10, blue: 0.16, alpha: 1.0),
            NSColor(red: 0.03, green: 0.04, blue: 0.08, alpha: 1.0)
        ]
    )
    gradient?.draw(in: outerPath, angle: -45)

    // Subtle Outer Rim
    NSColor(red: 0.25, green: 0.45, blue: 0.85, alpha: 0.35).setStroke()
    outerPath.lineWidth = 4 * scale
    outerPath.stroke()

    context.saveGState()
    outerPath.addClip()

    // Inner Grid lines
    let gridPath = NSBezierPath()
    gridPath.lineWidth = 1 * scale
    NSColor(red: 0.2, green: 0.3, blue: 0.5, alpha: 0.12).setStroke()
    let step: CGFloat = 40 * scale
    var x: CGFloat = margin
    while x <= size - margin {
        gridPath.move(to: NSPoint(x: x, y: margin))
        gridPath.line(to: NSPoint(x: x, y: size - margin))
        x += step
    }
    var y: CGFloat = margin
    while y <= size - margin {
        gridPath.move(to: NSPoint(x: margin, y: y))
        gridPath.line(to: NSPoint(x: size - margin, y: y))
        y += step
    }
    gridPath.stroke()

    // Terminal Window Container
    let termX = 140 * scale
    let termY = 160 * scale
    let termW = 744 * scale
    let termH = 704 * scale
    let termCorner: CGFloat = 28 * scale
    let termRect = NSRect(x: termX, y: termY, width: termW, height: termH)
    let termPath = NSBezierPath(roundedRect: termRect, xRadius: termCorner, yRadius: termCorner)

    NSColor(red: 0.06, green: 0.08, blue: 0.13, alpha: 0.95).setFill()
    termPath.fill()

    NSColor(red: 0.2, green: 0.35, blue: 0.65, alpha: 0.4).setStroke()
    termPath.lineWidth = 2 * scale
    termPath.stroke()

    // Titlebar
    let barH: CGFloat = 80 * scale
    let barRect = NSRect(x: termX, y: termY + termH - barH, width: termW, height: barH)
    let barPath = NSBezierPath(roundedRect: barRect, xRadius: termCorner, yRadius: termCorner)
    NSColor(red: 0.10, green: 0.14, blue: 0.22, alpha: 1.0).setFill()
    barPath.fill()

    // Window Dots
    let dotY = termY + termH - (barH / 2.0) - (11 * scale)
    let dotColors = [
        NSColor(red: 0.98, green: 0.36, blue: 0.35, alpha: 1.0),
        NSColor(red: 0.98, green: 0.74, blue: 0.24, alpha: 1.0),
        NSColor(red: 0.34, green: 0.85, blue: 0.44, alpha: 1.0)
    ]
    for (i, color) in dotColors.enumerated() {
        let dotX = termX + (36 * scale) + CGFloat(i) * (34 * scale)
        let dot = NSBezierPath(ovalIn: NSRect(x: dotX, y: dotY, width: 22 * scale, height: 22 * scale))
        color.setFill()
        dot.fill()
    }

    // Modern Neon Terminal Prompt ">_"
    // Glow effect for Chevron
    let chevGlow = NSBezierPath()
    chevGlow.move(to: NSPoint(x: 230 * scale, y: 580 * scale))
    chevGlow.line(to: NSPoint(x: 350 * scale, y: 480 * scale))
    chevGlow.line(to: NSPoint(x: 230 * scale, y: 380 * scale))
    chevGlow.lineWidth = 36 * scale
    chevGlow.lineCapStyle = .round
    chevGlow.lineJoinStyle = .round
    NSColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 0.25).setStroke()
    chevGlow.stroke()

    let chev = NSBezierPath()
    chev.move(to: NSPoint(x: 230 * scale, y: 580 * scale))
    chev.line(to: NSPoint(x: 350 * scale, y: 480 * scale))
    chev.line(to: NSPoint(x: 230 * scale, y: 380 * scale))
    chev.lineWidth = 26 * scale
    chev.lineCapStyle = .round
    chev.lineJoinStyle = .round
    NSColor(red: 0.1, green: 0.9, blue: 1.0, alpha: 1.0).setStroke()
    chev.stroke()

    // Cursor Pulse "_"
    let cursorGlow = NSBezierPath()
    cursorGlow.move(to: NSPoint(x: 400 * scale, y: 380 * scale))
    cursorGlow.line(to: NSPoint(x: 520 * scale, y: 380 * scale))
    cursorGlow.lineWidth = 36 * scale
    cursorGlow.lineCapStyle = .round
    NSColor(red: 0.2, green: 1.0, blue: 0.6, alpha: 0.25).setStroke()
    cursorGlow.stroke()

    let cursor = NSBezierPath()
    cursor.move(to: NSPoint(x: 400 * scale, y: 380 * scale))
    cursor.line(to: NSPoint(x: 520 * scale, y: 380 * scale))
    cursor.lineWidth = 26 * scale
    cursor.lineCapStyle = .round
    NSColor(red: 0.3, green: 1.0, blue: 0.7, alpha: 1.0).setStroke()
    cursor.stroke()

    // Network / Signal Constellation Topology
    let p1 = NSPoint(x: 610 * scale, y: 560 * scale)
    let p2 = NSPoint(x: 750 * scale, y: 620 * scale)
    let p3 = NSPoint(x: 740 * scale, y: 440 * scale)
    let p4 = NSPoint(x: 640 * scale, y: 340 * scale)

    let netEdges = [(p1, p2), (p1, p3), (p3, p4), (p2, p3)]
    let edgePath = NSBezierPath()
    edgePath.lineWidth = 4 * scale
    for (start, end) in netEdges {
        edgePath.move(to: start)
        edgePath.line(to: end)
    }
    NSColor(red: 0.4, green: 0.65, blue: 1.0, alpha: 0.6).setStroke()
    edgePath.stroke()

    let nodes = [p1, p2, p3, p4]
    for pt in nodes {
        let halo = NSBezierPath(ovalIn: NSRect(x: pt.x - 20 * scale, y: pt.y - 20 * scale, width: 40 * scale, height: 40 * scale))
        NSColor(red: 0.0, green: 0.85, blue: 1.0, alpha: 0.3).setFill()
        halo.fill()

        let core = NSBezierPath(ovalIn: NSRect(x: pt.x - 11 * scale, y: pt.y - 11 * scale, width: 22 * scale, height: 22 * scale))
        NSColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 1.0).setFill()
        core.fill()

        let center = NSBezierPath(ovalIn: NSRect(x: pt.x - 5 * scale, y: pt.y - 5 * scale, width: 10 * scale, height: 10 * scale))
        NSColor.white.setFill()
        center.fill()
    }

    context.restoreGState()
    image.unlockFocus()

    guard let tiffData = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiffData),
          let pngData = rep.representation(using: .png, properties: [:]) else {
        return
    }

    try? pngData.write(to: URL(fileURLWithPath: outputPath))
}

let assetDir = "/Users/jackson-hao/code/AeroTerm/Assets"
let iconsetDir = "\(assetDir)/AppIcon.iconset"
let fileManager = FileManager.default

try? fileManager.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in sizes {
    generateIcon(size: size, outputPath: "\(iconsetDir)/\(name)")
}

generateIcon(size: 1024, outputPath: "\(assetDir)/AppIcon_1024.png")

print("Generated all iconset sizes. Now building .icns with iconutil...")

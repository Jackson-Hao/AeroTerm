import AppKit
import CoreText
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath)
let iconURL = root.appendingPathComponent("Assets/AppIcon_1024.png")
let fontURL = root.appendingPathComponent("Sources/AeroTerm/Resources/Fonts/CascadiaCodeNF-Bold.otf")
let outURL = root.appendingPathComponent("Assets/readme-hero.png")

CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)

let width: CGFloat = 1600
let height: CGFloat = 520
let scale: CGFloat = 2
let pixelWidth = Int(width * scale)
let pixelHeight = Int(height * scale)

guard let icon = NSImage(contentsOf: iconURL) else {
    fputs("missing AppIcon_1024.png\n", stderr)
    exit(1)
}

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: pixelWidth,
    height: pixelHeight,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    exit(1)
}

ctx.scaleBy(x: scale, y: scale)

let bg = NSColor(calibratedRed: 7 / 255, green: 11 / 255, blue: 20 / 255, alpha: 1)
ctx.setFillColor(bg.cgColor)
ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

ctx.saveGState()
ctx.setStrokeColor(NSColor(calibratedRed: 18 / 255, green: 32 / 255, blue: 56 / 255, alpha: 0.7).cgColor)
ctx.setLineWidth(1)
let step: CGFloat = 28
var x: CGFloat = 0
while x <= width {
    ctx.move(to: CGPoint(x: x, y: 0))
    ctx.addLine(to: CGPoint(x: x, y: height))
    x += step
}
var y: CGFloat = 0
while y <= height {
    ctx.move(to: CGPoint(x: 0, y: y))
    ctx.addLine(to: CGPoint(x: width, y: y))
    y += step
}
ctx.strokePath()
ctx.restoreGState()

let glowCenter = CGPoint(x: 250, y: height / 2)
let glowColors = [
    NSColor(calibratedRed: 0, green: 0.78, blue: 0.92, alpha: 0.28).cgColor,
    NSColor(calibratedRed: 0, green: 0.78, blue: 0.92, alpha: 0).cgColor
] as CFArray
if let gradient = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0, 1]) {
    ctx.drawRadialGradient(
        gradient,
        startCenter: glowCenter,
        startRadius: 10,
        endCenter: glowCenter,
        endRadius: 240,
        options: []
    )
}

let iconSize: CGFloat = 268
let iconRect = CGRect(x: 116, y: (height - iconSize) / 2, width: iconSize, height: iconSize)
if let cgIcon = icon.cgImage(forProposedRect: nil, context: nil, hints: nil) {
    ctx.draw(cgIcon, in: iconRect)
}

func drawText(_ string: String, font: NSFont, color: NSColor, at point: CGPoint, tracking: CGFloat = 0) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .kern: tracking
    ]
    let ns = NSAttributedString(string: string, attributes: attrs)
    let line = CTLineCreateWithAttributedString(ns)
    ctx.saveGState()
    ctx.textPosition = point
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

let titleFont = NSFont(name: "CascadiaCodeNF-Bold", size: 72)
    ?? NSFont.monospacedSystemFont(ofSize: 72, weight: .bold)
let title = "AeroTerm"
let titlePoint = CGPoint(x: 430, y: 278)
drawText(
    title,
    font: titleFont,
    color: NSColor(calibratedWhite: 0.96, alpha: 1),
    at: titlePoint,
    tracking: 1.2
)

ctx.setFillColor(NSColor(calibratedRed: 0.16, green: 0.86, blue: 0.95, alpha: 1).cgColor)
ctx.fill(CGRect(x: 434, y: 258, width: 92, height: 4))

let subFont = NSFont.systemFont(ofSize: 22, weight: .medium)
drawText(
    "Native macOS workbench  ·  SSH  ·  Serial  ·  Desktop  ·  Agents",
    font: subFont,
    color: NSColor(calibratedRed: 0.62, green: 0.72, blue: 0.82, alpha: 1),
    at: CGPoint(x: 434, y: 198)
)

let pills = ["SSH", "SFTP", "Serial", "TCP/UDP", "HTTP", "VNC", "RDP", "Agent CLI"]
let pillFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
var pillX: CGFloat = 434
let pillY: CGFloat = 128
for label in pills {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: pillFont,
        .foregroundColor: NSColor(calibratedRed: 0.55, green: 0.92, blue: 0.98, alpha: 1)
    ]
    let ns = NSAttributedString(string: label, attributes: attrs)
    let size = ns.size()
    let rect = CGRect(x: pillX, y: pillY, width: size.width + 22, height: 28)
    let path = CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
    ctx.setStrokeColor(NSColor(calibratedRed: 0.2, green: 0.62, blue: 0.78, alpha: 0.7).cgColor)
    ctx.setFillColor(NSColor(calibratedRed: 0.08, green: 0.18, blue: 0.28, alpha: 0.9).cgColor)
    ctx.addPath(path)
    ctx.drawPath(using: .fillStroke)
    ctx.saveGState()
    ctx.textPosition = CGPoint(x: pillX + 11, y: pillY + 8)
    CTLineDraw(CTLineCreateWithAttributedString(ns), ctx)
    ctx.restoreGState()
    pillX += rect.width + 10
}

guard let image = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
rep.size = NSSize(width: width, height: height)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: outURL)
print("wrote \(outURL.path)")

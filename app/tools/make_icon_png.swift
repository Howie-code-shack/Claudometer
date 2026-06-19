// Generates claudometer-icon.png (1024×1024) — a gauge/dial app icon that
// mirrors the menu-bar glyph: a speedometer arc with a teal→amber→coral scale
// band and a white needle, on a warm clay squircle.
//
// Run from app/:  swift tools/make_icon_png.swift   (then ./make_app_icon.sh to build the .icns)
import AppKit
import Foundation

let S = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: S, pixelsHigh: S,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Background squircle with a clay gradient.
let inset: CGFloat = 96
let bgRect = NSRect(x: inset, y: inset, width: CGFloat(S) - 2 * inset, height: CGFloat(S) - 2 * inset)
let bg = NSBezierPath(roundedRect: bgRect, xRadius: 185, yRadius: 185)
let grad = NSGradient(
    starting: NSColor(red: 0.89, green: 0.51, blue: 0.42, alpha: 1),
    ending:   NSColor(red: 0.74, green: 0.32, blue: 0.22, alpha: 1))!
grad.draw(in: bg, angle: -90)

// Gauge geometry.
let cx: CGFloat = 512, cy: CGFloat = 430
let R: CGFloat = 300
let band: CGFloat = 72

func arcSegment(_ start: CGFloat, _ end: CGFloat, _ color: NSColor) {
    let p = NSBezierPath()
    p.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: R, startAngle: start, endAngle: end)
    p.lineWidth = band
    p.lineCapStyle = .butt
    color.setStroke()
    p.stroke()
}

// Scale band, split at the app's 70% / 90% thresholds (left = low usage).
// Matches UsagePalette: teal → amber → coral.
let teal  = NSColor(red: 0.12, green: 0.71, blue: 0.65, alpha: 1)
let amber = NSColor(red: 0.96, green: 0.66, blue: 0.23, alpha: 1)
let coral = NSColor(red: 0.95, green: 0.33, blue: 0.36, alpha: 1)
arcSegment(54, 180, teal)    // 0–70%
arcSegment(18, 54, amber)    // 70–90%
arcSegment(0, 18, coral)     // 90–100%

// Needle pointing to ~72% (just into the yellow), white.
let needleAngle = (180.0 - 72.0 * 1.8) * Double.pi / 180.0
let needleLen = R - 8
let tip = NSPoint(x: cx + needleLen * CGFloat(cos(needleAngle)),
                  y: cy + needleLen * CGFloat(sin(needleAngle)))
let needle = NSBezierPath()
needle.move(to: NSPoint(x: cx, y: cy))
needle.line(to: tip)
needle.lineWidth = 30
needle.lineCapStyle = .round
NSColor.white.setStroke()
needle.stroke()

// Center hub.
let hubR: CGFloat = 52
NSColor.white.setFill()
NSBezierPath(ovalIn: NSRect(x: cx - hubR, y: cy - hubR, width: hubR * 2, height: hubR * 2)).fill()
let innerR: CGFloat = 22
NSColor(red: 0.74, green: 0.32, blue: 0.22, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: cx - innerR, y: cy - innerR, width: innerR * 2, height: innerR * 2)).fill()

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("Failed to encode PNG\n".utf8))
    exit(1)
}
try data.write(to: URL(fileURLWithPath: "claudometer-icon.png"))
print("✅ Wrote claudometer-icon.png (\(S)×\(S))")

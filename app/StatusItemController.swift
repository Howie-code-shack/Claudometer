import AppKit

// MARK: - Menu-bar icon rendering
//
// Owns drawing the spark glyph and the percentage title. The color IS the
// status signal (green/yellow/red), so the icon is deliberately NOT a monochrome
// template image — adapting to the menu-bar appearance would throw away the very
// information the icon exists to convey.
final class StatusItemController {
    private weak var statusItem: NSStatusItem?

    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
    }

    /// Render the menu-bar item.
    /// - Parameters:
    ///   - percentage: utilization 0–100, or nil when not connected / no data.
    func update(percentage: Int?) {
        guard let button = statusItem?.button else { return }

        guard let percentage else {
            // Not connected / no data yet — show a neutral dial + dash, not a misleading 0%.
            button.image = gaugeIcon(percentage: nil, color: .secondaryLabelColor)
            button.title = " –"
            return
        }

        button.image = gaugeIcon(percentage: percentage, color: color(for: percentage))
        button.title = " \(percentage)%"
    }

    // Matches the popover's signature teal → amber → coral ramp (UsagePalette),
    // so the menu-bar gauge and the in-popover dials read as one instrument.
    private func color(for percentage: Int) -> NSColor {
        if percentage < 70 {
            return NSColor(red: 0.12, green: 0.71, blue: 0.65, alpha: 1.0) // Teal
        } else if percentage < 90 {
            return NSColor(red: 0.96, green: 0.66, blue: 0.23, alpha: 1.0) // Amber
        } else {
            return NSColor(red: 0.95, green: 0.33, blue: 0.36, alpha: 1.0) // Coral
        }
    }

    // A speedometer-style dial: an upper-semicircle arc with a needle whose
    // angle encodes usage (0% → left, 100% → right). The stroke color carries
    // the same green/yellow/red status signal as before. `percentage == nil`
    // renders the dial with the needle parked at 0 (not-connected state).
    private func gaugeIcon(percentage: Int?, color: NSColor) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)

        image.lockFocus()

        let cx: CGFloat = 8, cy: CGFloat = 5.5
        let r: CGFloat = 5.5

        // Dial arc — the upper semicircle (180° on the left to 0° on the right).
        let arc = NSBezierPath()
        arc.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: r, startAngle: 0, endAngle: 180)
        arc.lineWidth = 1.6
        arc.lineCapStyle = .round
        color.setStroke()
        arc.stroke()

        // Needle: map 0–100% onto 180°–0°.
        let pct = Double(min(max(percentage ?? 0, 0), 100))
        let angle = (180.0 - pct * 1.8) * Double.pi / 180.0
        let needleLen = r - 0.9
        let tip = NSPoint(x: cx + needleLen * CGFloat(cos(angle)),
                          y: cy + needleLen * CGFloat(sin(angle)))
        let needle = NSBezierPath()
        needle.move(to: NSPoint(x: cx, y: cy))
        needle.line(to: tip)
        needle.lineWidth = 1.4
        needle.lineCapStyle = .round
        needle.stroke()

        // Center hub.
        let hubR: CGFloat = 1.3
        let hub = NSBezierPath(ovalIn: NSRect(x: cx - hubR, y: cy - hubR, width: hubR * 2, height: hubR * 2))
        color.setFill()
        hub.fill()

        image.unlockFocus()
        image.isTemplate = false

        return image
    }
}

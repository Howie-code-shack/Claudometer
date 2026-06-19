import SwiftUI

// MARK: - Signature palette
//
// A graduated teal → amber → coral ramp. Deliberately NOT a green/yellow/red
// traffic light: the sweep from a cool "safe" hue to a warm "danger" hue is the
// app's visual signature and reads as a continuous instrument scale, not three
// stoplight states. Thresholds match the rest of the app (70 / 90).
enum UsagePalette {
    static let safe    = Color(red: 0.12, green: 0.71, blue: 0.65)  // teal
    static let caution = Color(red: 0.96, green: 0.66, blue: 0.23)  // amber
    static let danger  = Color(red: 0.95, green: 0.33, blue: 0.36)  // coral

    /// Color for a 0...1 utilization fraction.
    static func color(for fraction: Double) -> Color {
        let pct = fraction * 100
        if pct < 70 { return safe }
        if pct < 90 { return caution }
        return danger
    }
}

// MARK: - Gauge geometry
//
// A 270° dial with a 90° gap at the bottom: 0% sits lower-left, sweeps up and
// over the top, 100% lands lower-right — like a real speedometer. In SwiftUI's
// y-down space, 90° is straight down, so 135° is lower-left and a +270° sweep
// (clockwise on screen) ends at lower-right.
private let gaugeStart: Double = 135
private let gaugeSweep: Double = 270
private let redlineStart: Double = 0.85   // fraction where the danger zone begins

private func gaugeAngle(_ fraction: Double) -> Double {
    gaugeStart + min(max(fraction, 0), 1) * gaugeSweep
}

/// The dial arc — used for both the faint full track and the colored value arc.
private struct GaugeArc: Shape {
    var fraction: Double
    var lineWidth: CGFloat
    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let radius = (min(rect.width, rect.height) - lineWidth) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.addArc(center: center, radius: radius,
                    startAngle: .degrees(gaugeStart),
                    endAngle: .degrees(gaugeAngle(fraction)),
                    clockwise: false)
        return path
    }
}

/// The fixed coral "redline" segment near the top of the scale.
private struct GaugeRedline: Shape {
    var lineWidth: CGFloat
    func path(in rect: CGRect) -> Path {
        let radius = (min(rect.width, rect.height) - lineWidth) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.addArc(center: center, radius: radius,
                    startAngle: .degrees(gaugeStart + redlineStart * gaugeSweep),
                    endAngle: .degrees(gaugeStart + gaugeSweep),
                    clockwise: false)
        return path
    }
}

/// Evenly spaced tick marks around the arc.
private struct GaugeTicks: Shape {
    var count: Int
    var length: CGFloat
    func path(in rect: CGRect) -> Path {
        let outer = min(rect.width, rect.height) / 2
        let inner = outer - length
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        for i in 0..<count {
            let fraction = Double(i) / Double(count - 1)
            let a = gaugeAngle(fraction) * .pi / 180
            path.move(to: CGPoint(x: center.x + inner * cos(a), y: center.y + inner * sin(a)))
            path.addLine(to: CGPoint(x: center.x + outer * cos(a), y: center.y + outer * sin(a)))
        }
        return path
    }
}

/// The needle — a pointer that animates to the current value.
private struct GaugeNeedle: Shape {
    var fraction: Double
    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let a = gaugeAngle(fraction) * .pi / 180
        let tip = CGPoint(x: center.x + (radius - 5) * cos(a),
                          y: center.y + (radius - 5) * sin(a))
        var path = Path()
        path.move(to: center)
        path.addLine(to: tip)
        return path
    }
}

// MARK: - Gauge dial
//
// The app's signature element: one tick-ringed needle gauge per usage window.
// The needle and value arc animate to the current reading whenever it changes
// (or the popover opens), so the cluster sweeps to life like an instrument panel.
struct GaugeDial: View {
    var fraction: Double          // 0...1
    var label: String
    var detail: String?           // e.g. countdown to reset

    @State private var shown: Double
    @Environment(\.colorScheme) private var scheme

    init(fraction: Double, label: String, detail: String? = nil) {
        self.fraction = fraction
        self.label = label
        self.detail = detail
        // Start at the real value so the first paint is correct; the needle then
        // springs to any later reading when usage refreshes.
        _shown = State(initialValue: fraction)
    }

    private let dialSize: CGFloat = 92
    private let ring: CGFloat = 3.5

    // A white instrument face in light mode; an inverted "sport tach" dark face
    // in dark mode. Keeps the gauge identity legible in both appearances.
    private var faceColor: Color {
        scheme == .dark
            ? Color(red: 0.11, green: 0.12, blue: 0.15)
            : Color(red: 0.99, green: 0.98, blue: 0.96)
    }
    private var tickColor: Color {
        Color.secondary.opacity(scheme == .dark ? 0.55 : 0.40)
    }
    private var valueColor: Color { UsagePalette.color(for: shown) }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(faceColor)
                    .overlay(Circle().strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5))
                    .shadow(color: .black.opacity(scheme == .dark ? 0.0 : 0.10), radius: 2, y: 1)

                // Faint full-scale track.
                GaugeArc(fraction: 1, lineWidth: ring)
                    .stroke(tickColor.opacity(0.35), lineWidth: ring)

                GaugeTicks(count: 11, length: 4)
                    .stroke(tickColor, lineWidth: 1)

                GaugeRedline(lineWidth: ring)
                    .stroke(UsagePalette.danger.opacity(0.9), lineWidth: ring)

                // Colored value arc.
                GaugeArc(fraction: shown, lineWidth: ring)
                    .stroke(valueColor, style: StrokeStyle(lineWidth: ring, lineCap: .round))

                GaugeNeedle(fraction: shown)
                    .stroke(valueColor, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))

                // Mask the needle's inner half so it reads as a rim pointer, and
                // give the readout a clean disc to sit on (doubles as the hub).
                Circle()
                    .fill(faceColor)
                    .frame(width: 44, height: 44)
                    .overlay(Circle().strokeBorder(valueColor.opacity(0.20), lineWidth: 1))

                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(Int((shown * 100).rounded()))")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text("%")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .baselineOffset(1)
                }
            }
            .frame(width: dialSize, height: dialSize)

            VStack(spacing: 1) {
                Text(label.uppercased())
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.primary.opacity(0.65))
                }
            }
        }
        .onChange(of: fraction) { newValue in
            withAnimation(.spring(response: 0.85, dampingFraction: 0.82)) {
                shown = newValue
            }
        }
    }
}

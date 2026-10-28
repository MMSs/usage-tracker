import SwiftUI

/// The app icon's three usage rings without the squircle, in the foreground
/// style: faint full tracks under solid arcs. Stands for the app itself
/// where no provider applies yet.
struct AppMark: View {
    var body: some View {
        ZStack {
            AppMarkRings(part: .tracks).opacity(0.3)
            AppMarkRings(part: .arcs)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// One layer of the mark. Proportions follow `scripts/make-icon.swift`, with
/// slightly heavier strokes so the rings hold up at menu bar size.
struct AppMarkRings: Shape {
    enum Part {
        case tracks, arcs
    }

    let part: Part

    /// Outer to inner, as on the app icon.
    static let fills: [Double] = [0.70, 0.41, 0.53]
    /// Fractions of the mark's side.
    static let lineWidth: CGFloat = 0.10
    static let pitch: CGFloat = 0.155

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let lineWidth = Self.lineWidth * side
        var rings = Path()

        for (index, fill) in Self.fills.enumerated() {
            let radius = side / 2 - lineWidth / 2 - CGFloat(index) * Self.pitch * side
            let start = Angle.degrees(-90)
            // Clockwise on screen from 12 o'clock; SwiftUI's y points down.
            let end = part == .tracks ? start + .degrees(360) : start + .degrees(360 * fill)
            var ring = Path()
            ring.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
            rings.addPath(ring.strokedPath(StrokeStyle(lineWidth: lineWidth, lineCap: .round)))
        }

        return rings
    }
}

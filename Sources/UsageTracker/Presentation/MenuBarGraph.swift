import SwiftUI

/// One graph in the style the appearance picks, drawn at the size
/// `MenuBarGraphGeometry` reports. A new style adds a case here and a private
/// view below.
struct MenuBarGraph: View {
    let style: MenuBarGraphStyle
    let meters: [MenuBarMeter]
    let palette: MenuBarPalette

    var body: some View {
        switch style {
        case .rings:
            MenuBarRing(meters: meters, palette: palette)
        case .bars:
            MenuBarBars(meters: meters, palette: palette)
        }
    }
}

/// The last meter is the outer ring, the first the innermost, each filling
/// clockwise from twelve. A meter with a tick draws it across its own ring.
private struct MenuBarRing: View {
    let meters: [MenuBarMeter]
    let palette: MenuBarPalette

    private var diameter: CGFloat { MenuBarGraphGeometry.size(.rings, meterCount: meters.count).width }
    private let lineWidth: CGFloat = 2.5
    private let gap: CGFloat = 1.5

    var body: some View {
        ZStack {
            ForEach(Array(meters.enumerated()), id: \.offset) { index, meter in
                let depth = CGFloat(meters.count - 1 - index)
                let inset = lineWidth / 2 + depth * (lineWidth + gap)

                arc(meter, inset: inset)

                if let tick = meter.tick {
                    // Crosses its ring and pokes into the gap inside it.
                    Capsule()
                        .fill(palette.tick)
                        .frame(width: 1.5, height: lineWidth + 2)
                        .offset(y: -(diameter / 2 - depth * (lineWidth + gap) - (lineWidth + 2) / 2))
                        .rotationEffect(.degrees(tick * 360))
                }
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private func arc(_ meter: MenuBarMeter, inset: CGFloat) -> some View {
        ZStack {
            Circle()
                .inset(by: inset)
                .stroke(palette.track, lineWidth: lineWidth)

            if let fraction = meter.fraction, fraction > 0 {
                Circle()
                    .inset(by: inset)
                    .trim(from: 0, to: fraction)
                    .stroke(palette.fill(meter.tint), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

/// Top to bottom in array order.
private struct MenuBarBars: View {
    let meters: [MenuBarMeter]
    let palette: MenuBarPalette

    private var width: CGFloat { MenuBarGraphGeometry.size(.bars, meterCount: meters.count).width }
    private let barHeight = MenuBarGraphGeometry.barHeight

    var body: some View {
        VStack(spacing: MenuBarGraphGeometry.barSpacing) {
            ForEach(Array(meters.enumerated()), id: \.offset) { _, meter in
                bar(meter)
            }
        }
    }

    private func bar(_ meter: MenuBarMeter) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(palette.track)

            if let fraction = meter.fraction, fraction > 0 {
                Capsule()
                    .fill(palette.fill(meter.tint))
                    .frame(width: max(barHeight, width * fraction))
            }
        }
        .frame(width: width, height: barHeight)
        .overlay(alignment: .leading) {
            if let tick = meter.tick {
                Capsule()
                    .fill(palette.tick)
                    .frame(width: 1.5, height: barHeight + 2)
                    .offset(x: width * tick - 0.75)
            }
        }
    }
}

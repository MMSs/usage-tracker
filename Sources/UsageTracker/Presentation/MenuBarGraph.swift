import SwiftUI

/// One graph in the style the appearance picks, drawn at the size
/// `MenuBarGraphGeometry` reports. A new style adds a case here and a private
/// view below.
struct MenuBarGraph: View {
    let style: MenuBarGraphStyle
    let meters: [MenuBarMeter]
    let palette: MenuBarPalette

    var body: some View {
        let size = MenuBarGraphGeometry.size(style, meterCount: meters.count)

        content
            .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .rings:
            MenuBarRing(meters: meters, palette: palette)
        case .bars:
            MenuBarBars(meters: meters, palette: palette)
        case .battery:
            MenuBarBattery(meters: meters, palette: palette)
        case .columns:
            MenuBarColumns(meters: meters, palette: palette)
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

/// What remains, left to right: the first meter on top, the last below, or one
/// meter alone filling the body. The nub sits on the right.
private struct MenuBarBattery: View {
    let meters: [MenuBarMeter]
    let palette: MenuBarPalette

    private let frame = MenuBarGraphGeometry.batterySize
    private let bodyWidth = MenuBarGraphGeometry.batteryBodyWidth
    private let inset = MenuBarGraphGeometry.batteryInset
    private let nub = MenuBarGraphGeometry.batteryNubSize
    private let tickWidth: CGFloat = 1.5

    private var innerWidth: CGFloat { bodyWidth - 2 * inset }
    private var innerHeight: CGFloat { frame.height - 2 * inset }
    private var fillGap: CGFloat { 1 }
    private var fillHeight: CGFloat {
        meters.count > 1 ? (innerHeight - fillGap) / 2 : innerHeight
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3.5)
                .strokeBorder(palette.track, lineWidth: 1)
                .frame(width: bodyWidth, height: frame.height)

            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 1, topTrailingRadius: 1)
                .fill(palette.track)
                .frame(width: nub.width, height: nub.height)
                .offset(x: bodyWidth, y: (frame.height - nub.height) / 2)

            ForEach(Array(meters.prefix(2).enumerated()), id: \.offset) { index, meter in
                let top = inset + CGFloat(index) * (fillHeight + fillGap)

                if let remaining = MenuBarGraphGeometry.batteryFill(meter.fraction), remaining > 0 {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(palette.fill(meter.tint))
                        .frame(width: innerWidth * min(remaining, 1), height: fillHeight)
                        .offset(x: inset, y: top)
                }

                if let tick = meter.tick {
                    // Two points taller than its fill, so it stays inside the frame.
                    Capsule()
                        .fill(palette.tick)
                        .frame(width: tickWidth, height: fillHeight + 2)
                        .offset(x: inset + innerWidth * (1 - tick) - tickWidth / 2, y: top - 1)
                }
            }
        }
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
    }
}

/// Left to right in array order, each filling from the bottom.
private struct MenuBarColumns: View {
    let meters: [MenuBarMeter]
    let palette: MenuBarPalette

    private let width = MenuBarGraphGeometry.columnWidth
    private let height = MenuBarGraphGeometry.columnHeight
    private let tickThickness: CGFloat = 1.5

    var body: some View {
        HStack(spacing: MenuBarGraphGeometry.columnSpacing) {
            ForEach(Array(meters.enumerated()), id: \.offset) { index, meter in
                column(meter, index: index)
            }
        }
    }

    private func column(_ meter: MenuBarMeter, index: Int) -> some View {
        // The tick is two points wider than its bar, but only into the gap
        // beside a neighbour: an outer edge would leave the frame.
        let before: CGFloat = index > 0 ? 1 : 0
        let after: CGFloat = index < meters.count - 1 ? 1 : 0

        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(palette.track)

            if let fraction = meter.fraction, fraction > 0 {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(palette.fill(meter.tint))
                    .frame(height: height * min(fraction, 1))
            }
        }
        .frame(width: width, height: height)
        .overlay(alignment: .bottomLeading) {
            if let tick = meter.tick {
                let center = min(max(height * tick, tickThickness / 2), height - tickThickness / 2)

                Capsule()
                    .fill(palette.tick)
                    .frame(width: width + before + after, height: tickThickness)
                    .offset(x: -before, y: -(center - tickThickness / 2))
            }
        }
    }
}

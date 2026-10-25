import SwiftUI

/// One graph in the style the appearance picks, drawn at the size
/// `MenuBarGraphGeometry` reports. A new style adds a case here and a private
/// view below.
struct MenuBarGraph: View {
    let style: MenuBarGraphStyle
    let meters: [MenuBarMeter]
    let palette: MenuBarPalette
    var now: Date = Date()

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
        case .gauge:
            MenuBarGauge(meters: meters, palette: palette)
        case .segments:
            MenuBarSegments(meters: meters, palette: palette)
        case .columns:
            MenuBarColumns(meters: meters, palette: palette)
        case .pie:
            MenuBarPie(meters: meters, palette: palette)
        case .sparkline:
            MenuBarSparkline(meters: meters, palette: palette, now: now)
        case .dials:
            MenuBarDials(meters: meters, palette: palette)
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

/// Ten blocks per row, the first meter on top, lit from the left.
private struct MenuBarSegments: View {
    let meters: [MenuBarMeter]
    let palette: MenuBarPalette

    private let block = MenuBarGraphGeometry.segmentSize
    private let tickWidth: CGFloat = 1.5

    private var frame: CGSize { MenuBarGraphGeometry.size(.segments, meterCount: meters.count) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(meters.prefix(2).enumerated()), id: \.offset) { index, meter in
                let top = CGFloat(index) * (block.height + MenuBarGraphGeometry.segmentRowSpacing)
                let lit = MenuBarGraphGeometry.litSegments(meter.fraction)

                HStack(spacing: MenuBarGraphGeometry.segmentSpacing) {
                    ForEach(0..<MenuBarGraphGeometry.segmentCount, id: \.self) { segment in
                        RoundedRectangle(cornerRadius: 0.9)
                            .fill(segment < lit ? palette.fill(meter.tint) : palette.track)
                            .frame(width: block.width, height: block.height)
                    }
                }
                .offset(y: top)

                if let tick = meter.tick {
                    // Two points taller than its row, clamped to stay inside the frame.
                    let tickTop = max(top - 1, 0)
                    let tickBottom = min(top + block.height + 1, frame.height)
                    let center = min(max(frame.width * tick, tickWidth / 2), frame.width - tickWidth / 2)

                    Capsule()
                        .fill(palette.tick)
                        .frame(width: tickWidth, height: tickBottom - tickTop)
                        .offset(x: center - tickWidth / 2, y: tickTop)
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

/// A radial line across a band, kept inside the band's radii.
private func radialTick(center: CGPoint, angle: Angle, from inner: CGFloat, to outer: CGFloat) -> Path {
    let width: CGFloat = 1.5
    let direction = CGPoint(x: cos(angle.radians), y: sin(angle.radians))

    return Path { path in
        path.move(to: CGPoint(x: center.x + direction.x * (inner + width / 2), y: center.y + direction.y * (inner + width / 2)))
        path.addLine(to: CGPoint(x: center.x + direction.x * (outer - width / 2), y: center.y + direction.y * (outer - width / 2)))
    }
}

/// Half-arcs from nine o'clock over twelve to three, the last meter outermost
/// and the first four points in. The arcs share a centre one stroke-half above
/// the bottom edge, so strokes and caps stay inside the frame.
private struct MenuBarGauge: View {
    let meters: [MenuBarMeter]
    let palette: MenuBarPalette

    private let frame = MenuBarGraphGeometry.gaugeSize
    private let stroke = MenuBarGraphGeometry.gaugeStroke
    private let tickWidth: CGFloat = 1.5

    private var center: CGPoint { CGPoint(x: frame.width / 2, y: frame.height - stroke / 2) }

    var body: some View {
        ZStack {
            ForEach(Array(meters.prefix(2).enumerated()), id: \.offset) { index, meter in
                let depth = CGFloat(min(meters.count, 2) - 1 - index)
                let radius = MenuBarGraphGeometry.gaugeOuterRadius - stroke / 2 - depth * MenuBarGraphGeometry.gaugeArcSpacing

                arc(radius: radius, fraction: 1)
                    .stroke(palette.track, style: StrokeStyle(lineWidth: stroke, lineCap: .round))

                if let fraction = meter.fraction, fraction > 0 {
                    arc(radius: radius, fraction: min(fraction, 1))
                        .stroke(palette.fill(meter.tint), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                }

                if let tick = meter.tick {
                    radialTick(center: center, angle: .degrees(180 + 180 * tick), from: radius - stroke / 2 - 1, to: radius + stroke / 2)
                        .stroke(palette.tick, style: StrokeStyle(lineWidth: tickWidth, lineCap: .round))
                }
            }
        }
        .frame(width: frame.width, height: frame.height)
    }

    /// SwiftUI's y axis points down, so increasing angles run clockwise on screen.
    private func arc(radius: CGFloat, fraction: Double) -> Path {
        Path { path in
            path.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(180 + 180 * fraction), clockwise: false)
        }
    }
}

/// Wedges filling clockwise from twelve over one track disk. Two meters: the
/// last as an outer band, the first as a smaller wedge inside it.
private struct MenuBarPie: View {
    let meters: [MenuBarMeter]
    let palette: MenuBarPalette

    private let diameter = MenuBarGraphGeometry.pieDiameter

    private var center: CGPoint { CGPoint(x: diameter / 2, y: diameter / 2) }

    var body: some View {
        let shown = Array(meters.prefix(2))

        ZStack {
            Circle()
                .fill(palette.track)

            ForEach(Array(shown.enumerated()), id: \.offset) { index, meter in
                let band = band(index: index, count: shown.count)

                if let fraction = meter.fraction, fraction > 0 {
                    wedge(inner: band.inner, outer: band.outer, fraction: min(fraction, 1))
                        .fill(palette.fill(meter.tint))
                }

                if let tick = meter.tick {
                    radialTick(center: center, angle: .degrees(-90 + 360 * tick), from: band.inner, to: band.outer)
                        .stroke(palette.tick, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private func band(index: Int, count: Int) -> (inner: CGFloat, outer: CGFloat) {
        switch (count, index) {
        case (2, 0): (0, MenuBarGraphGeometry.pieInnerWedgeRadius)
        case (2, _): (MenuBarGraphGeometry.pieBandInnerRadius, diameter / 2)
        default: (0, diameter / 2)
        }
    }

    private func wedge(inner: CGFloat, outer: CGFloat, fraction: Double) -> Path {
        let start = Angle.degrees(-90)
        let end = Angle.degrees(-90 + 360 * fraction)

        return Path { path in
            path.addArc(center: center, radius: outer, startAngle: start, endAngle: end, clockwise: false)

            if inner > 0 {
                path.addArc(center: center, radius: inner, startAngle: end, endAngle: start, clockwise: true)
            } else {
                path.addLine(to: center)
            }

            path.closeSubpath()
        }
    }
}

/// The last twelve hours as a line, the first meter solid with a dot at the
/// live value and the second behind it at 0.45 opacity, over a hairline
/// baseline. A tick is a short dash at the right edge.
private struct MenuBarSparkline: View {
    let meters: [MenuBarMeter]
    let palette: MenuBarPalette
    let now: Date

    private let frame = MenuBarGraphGeometry.sparklineSize
    private let lineWidth: CGFloat = 1.5
    private let dot: CGFloat = 3
    private let tickSize = CGSize(width: 3, height: 1.5)

    /// Pulls a point in by half the line width, so the stroke and its round
    /// caps stay inside the frame at 0% and 100%.
    private func inset(_ point: CGPoint) -> CGPoint {
        let half = lineWidth / 2

        return CGPoint(
            x: half + point.x * (frame.width - lineWidth) / frame.width,
            y: half + point.y * (frame.height - lineWidth) / frame.height
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(palette.track)
                .frame(width: frame.width, height: 0.5)
                .offset(y: frame.height - 0.5)

            ForEach(Array(meters.prefix(2).enumerated()).reversed(), id: \.offset) { index, meter in
                let opacity = index == 0 ? 1.0 : 0.45
                let points = MenuBarGraphGeometry.sparklinePoints(
                    samples: meter.samples, current: meter.fraction, now: now, size: frame
                )

                if let end = points.last {
                    Path { path in
                        path.addLines(points.map(inset))
                    }
                    .stroke(palette.fill(meter.tint).opacity(opacity), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

                    if index == 0 {
                        Circle()
                            .fill(palette.fill(meter.tint))
                            .frame(width: dot, height: dot)
                            .offset(x: min(inset(end).x, frame.width - dot / 2) - dot / 2, y: min(max(inset(end).y, dot / 2), frame.height - dot / 2) - dot / 2)
                    }
                }

                if let tick = meter.tick {
                    let y = min(max(frame.height * (1 - min(max(tick, 0), 1)), tickSize.height / 2), frame.height - tickSize.height / 2)

                    Capsule()
                        .fill(palette.tick)
                        .frame(width: tickSize.width, height: tickSize.height)
                        .offset(x: frame.width - tickSize.width, y: y - tickSize.height / 2)
                }
            }
        }
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
    }
}

/// Short on the left; each a small ring filling clockwise from twelve with
/// its letter in the middle. A meter with a tick draws it as Rings does.
private struct MenuBarDials: View {
    let meters: [MenuBarMeter]
    let palette: MenuBarPalette

    private let diameter = MenuBarGraphGeometry.dialDiameter
    private let lineWidth: CGFloat = 2
    private let tickWidth: CGFloat = 1.5

    var body: some View {
        HStack(spacing: MenuBarGraphGeometry.dialSpacing) {
            ForEach(Array(meters.enumerated()), id: \.offset) { _, meter in
                dial(meter)
            }
        }
    }

    private func dial(_ meter: MenuBarMeter) -> some View {
        ZStack {
            Circle()
                .inset(by: lineWidth / 2)
                .stroke(palette.track, lineWidth: lineWidth)

            if let fraction = meter.fraction, fraction > 0 {
                Circle()
                    .inset(by: lineWidth / 2)
                    .trim(from: 0, to: min(fraction, 1))
                    .stroke(palette.fill(meter.tint), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            Text(meter.letter)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(palette.text(meter.tint))

            if let tick = meter.tick {
                // Crosses its ring and pokes into the space inside it.
                Capsule()
                    .fill(palette.tick)
                    .frame(width: tickWidth, height: lineWidth + 2)
                    .offset(y: -(diameter / 2 - (lineWidth + 2) / 2))
                    .rotationEffect(.degrees(tick * 360))
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

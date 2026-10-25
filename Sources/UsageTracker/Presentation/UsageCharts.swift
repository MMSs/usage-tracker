import SwiftUI

/// The progress bar a chart sits on.
struct ChartFloor {
    let fraction: Double
    let tint: PacingTint
    let tick: Double?
}

/// A chart and its row's progress bar as one rounded block, the bar flush
/// under the chart. The chart's first view fills the block above the bar;
/// any views after it (an axis, day names) run under the block. With no
/// floor the chart fills the block alone.
struct ChartedBarBlock<Chart: View>: View {
    let chartHeight: CGFloat
    let floor: ChartFloor?
    @ViewBuilder let chart: () -> Chart

    private static var floorHeight: CGFloat { 5 }

    var body: some View {
        Group(subviews: chart()) { subviews in
            VStack(alignment: .leading, spacing: 3) {
                VStack(spacing: 0) {
                    subviews.first
                        .frame(height: chartHeight)
                    if let floor {
                        floorBar(floor)
                    }
                }
                .background(.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 5))

                ForEach(subviews.dropFirst()) { subview in
                    subview
                }
            }
        }
    }

    /// Square-ended inside the block's corners; the tick rises into the chart.
    private func floorBar(_ floor: ChartFloor) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .bottomLeading) {
                Rectangle().fill(.primary.opacity(0.14))
                Rectangle()
                    .fill(floor.tint.color)
                    .frame(width: width * min(max(floor.fraction, 0), 1))
                if let tick = floor.tick {
                    Rectangle()
                        .fill(.primary)
                        .frame(width: 1.5, height: Self.floorHeight + 4)
                        .offset(x: min(max(width * tick - 0.75, 0), width - 1.5))
                }
            }
        }
        .frame(height: Self.floorHeight)
        .accessibilityHidden(true)
    }
}

/// The session's last day as a filled line, one piece per run of samples,
/// over a `24h ago · 12h · now` axis.
struct SessionHistoryChart: View {
    /// From `UsageChartLayout.sessionSegments` at a unit size, so 0...1 on
    /// both axes with y running down.
    let segments: [[CGPoint]]
    let tint: PacingTint

    var body: some View {
        ZStack {
            ForEach(segments.indices, id: \.self) { index in
                SegmentShape(points: segments[index], closed: true)
                    .fill(tint.chartColor.opacity(0.22))
                SegmentShape(points: segments[index], closed: false)
                    .stroke(tint.chartColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)

        ZStack {
            Text("24h ago").frame(maxWidth: .infinity, alignment: .leading)
            Text("12h")
            Text("now").frame(maxWidth: .infinity, alignment: .trailing)
        }
        .chartLabelStyle()
    }
}

/// One bar per day: today solid, past days muted, days to come and days
/// without data a faint slot. Hovering a bar names its day and value under
/// the block, in place of the day names when there are any.
struct DailyBarsChart: View {
    let bars: [DayBar]
    /// A dashed line at the even share, half the chart's height.
    let showsPaceLine: Bool
    let dayLabels: Bool
    /// Formats the hovered value; nil reads it as percent of a limit.
    let unit: BudgetUnit?

    @State private var hovered: Date?

    private static let locale = Locale(identifier: "en_US_POSIX")

    var body: some View {
        GeometryReader { proxy in
            let slot = proxy.size.width / CGFloat(max(bars.count, 1))

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(bars, id: \.day) { bar in
                        column(bar, height: proxy.size.height)
                            .frame(width: max(2, slot * 0.68), height: proxy.size.height, alignment: .bottom)
                            .frame(width: slot)
                            .contentShape(Rectangle())
                            .onHover { inside in
                                if inside {
                                    hovered = bar.day
                                } else if hovered == bar.day {
                                    hovered = nil
                                }
                            }
                    }
                }

                if showsPaceLine {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: proxy.size.height / 2))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height / 2))
                    }
                    .stroke(.primary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .allowsHitTesting(false)
                }
            }
        }
        .accessibilityHidden(true)

        ZStack {
            if dayLabels {
                HStack(spacing: 0) {
                    ForEach(bars, id: \.day) { bar in
                        Text(Self.dayName(bar.day))
                            .foregroundStyle(bar.isToday ? .secondary : .tertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .opacity(hoveredBar == nil ? 1 : 0)
            }

            Text(hoveredBar.map { Self.caption(for: $0, unit: unit) } ?? "\u{00A0}")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .chartLabelStyle()
        // The rows under the chart already give each day's label and value.
        .accessibilityHidden(true)
    }

    private var hoveredBar: DayBar? {
        hovered.flatMap { day in bars.first { $0.day == day } }
    }

    @ViewBuilder
    private func column(_ bar: DayBar, height: CGFloat) -> some View {
        if let value = bar.value, !bar.isFuture {
            if value > 0 {
                RoundedRectangle(cornerRadius: 2)
                    .fill(bar.tint.chartColor)
                    .opacity(bar.isToday ? 1 : 0.65)
                    .frame(height: max(1, height * bar.heightFraction))
            }
        } else {
            RoundedRectangle(cornerRadius: 1)
                .fill(.primary.opacity(0.12))
                .frame(height: 2)
        }
    }

    static func dayName(_ day: Date) -> String {
        day.formatted(.verbatim("\(weekday: .abbreviated)", locale: locale, timeZone: .current, calendar: .current))
    }

    /// "24 Oct · $4.20"; the day alone when it has no value.
    static func caption(for bar: DayBar, unit: BudgetUnit?) -> String {
        let date = bar.day.formatted(.verbatim("\(day: .defaultDigits) \(month: .abbreviated)", locale: locale, timeZone: .current, calendar: .current))
        guard let value = bar.value else {
            return date
        }

        return "\(date) · \((unit ?? .percent).format(Decimal(value)))"
    }
}

/// A polyline through unit points, or the area under it down to the bottom.
private struct SegmentShape: Shape {
    let points: [CGPoint]
    let closed: Bool

    func path(in rect: CGRect) -> Path {
        let scaled = points.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
        guard let first = scaled.first, let last = scaled.last else {
            return Path()
        }

        var path = Path()
        path.addLines(scaled)
        if closed {
            path.addLine(to: CGPoint(x: last.x, y: rect.maxY))
            path.addLine(to: CGPoint(x: first.x, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

private extension PacingTint {
    /// Uncoloured charts draw in the text colour rather than grey.
    var chartColor: Color {
        self == .neutral ? .primary : color
    }
}

private extension View {
    func chartLabelStyle() -> some View {
        font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
            .lineLimit(1)
    }
}

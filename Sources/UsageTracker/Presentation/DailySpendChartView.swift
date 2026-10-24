import SwiftUI

/// One bar per day of a cycle period. Past days are muted, today is solid,
/// and future days show only a faint track. Hovering a bar captures its day
/// and amount below the chart.
struct DailySpendChartView: View {
    let title: String
    let subtitleRow: (label: String, value: String)?
    let days: [DaySpend]
    let period: CyclePeriod
    let today: Date
    let unit: BudgetUnit

    private static let barHeight: CGFloat = 38
    private static let barSpacing: CGFloat = 2
    private static let locale = Locale(identifier: "en_US_POSIX")

    @State private var hovered: ChartBar?

    private var bars: [ChartBar] {
        ChartLayout.bars(days: days, period: period, today: today)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)

            if let subtitleRow {
                HStack {
                    Text(subtitleRow.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(subtitleRow.value)
                        .font(.caption.monospacedDigit())
                }
            }

            chart
                .frame(height: Self.barHeight)

            Text(hovered.map { Self.caption(for: $0, unit: unit) } ?? "\u{00A0}")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var chart: some View {
        GeometryReader { proxy in
            let items = bars
            let width = ChartLayout.barWidth(
                count: items.count,
                available: proxy.size.width,
                spacing: Self.barSpacing
            )

            HStack(alignment: .bottom, spacing: Self.barSpacing) {
                ForEach(items) { bar in
                    column(for: bar)
                        .frame(width: width, height: Self.barHeight)
                        .contentShape(Rectangle())
                        .onHover { inside in
                            if inside {
                                hovered = bar
                            } else if hovered == bar {
                                hovered = nil
                            }
                        }
                }
            }
        }
    }

    @ViewBuilder
    private func column(for bar: ChartBar) -> some View {
        ZStack(alignment: .bottom) {
            if bar.isFuture {
                Rectangle()
                    .fill(.primary.opacity(0.12))
            } else {
                Rectangle()
                    .fill(bar.isToday ? Color.primary : Color.primary.opacity(0.55))
                    .frame(height: Self.barHeight * bar.heightFraction)
            }
        }
    }

    static func caption(for bar: ChartBar, unit: BudgetUnit) -> String {
        let date = bar.day.formatted(.verbatim("\(day: .defaultDigits) \(month: .abbreviated)", locale: locale, timeZone: .current, calendar: .current))
        return "\(date) · \(unit.format(bar.amount))"
    }
}

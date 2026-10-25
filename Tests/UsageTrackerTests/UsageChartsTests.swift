import AppKit
import SwiftUI
import Testing
@testable import UsageTracker

private let chartCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
    return calendar
}()

private func chartDay(_ day: Int, hour: Int = 0) -> Date {
    chartCalendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
}

@MainActor
@Suite struct UsageChartsTests {
    private let floor = ChartFloor(fraction: 0.4, tint: .onPace, tick: 0.5)

    private let segments: [[CGPoint]] = [
        [CGPoint(x: 0, y: 0.9), CGPoint(x: 0.3, y: 0.5), CGPoint(x: 0.31, y: 1)],
        [CGPoint(x: 0.5, y: 1), CGPoint(x: 1, y: 0.6)],
    ]

    private let bars = (0..<7).map { offset in
        DayBar(
            day: chartDay(20 + offset), value: offset < 5 ? Double(offset * 4) : nil,
            heightFraction: Double(offset) / 8, tint: offset == 3 ? .overBudget : .onPace,
            isToday: offset == 4, isFuture: offset > 4
        )
    }

    /// Height in points of `view` rendered 268 wide.
    private func renderedHeight(_ view: some View) throws -> CGFloat {
        let renderer = ImageRenderer(content: view.frame(width: 268))
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        return CGFloat(image.height) / renderer.scale
    }

    @Test func everyChartRenders() throws {
        // The chart alone fills the block; the floor adds its 5pt bar.
        #expect(try renderedHeight(ChartedBarBlock(chartHeight: 26, floor: floor) { Color.clear }) == 31)
        #expect(try renderedHeight(ChartedBarBlock(chartHeight: 26, floor: nil) { Color.clear }) == 26)

        // The axis and day names run under the block.
        let session = try renderedHeight(ChartedBarBlock(chartHeight: 26, floor: floor) {
            SessionHistoryChart(segments: segments, tint: .onPace)
        })
        let bareSession = try renderedHeight(ChartedBarBlock(chartHeight: 26, floor: nil) {
            SessionHistoryChart(segments: segments, tint: .onPace)
        })
        #expect(session > 31)
        #expect(session - bareSession == 5)

        let week = try renderedHeight(ChartedBarBlock(chartHeight: 30, floor: floor) {
            DailyBarsChart(bars: bars, showsPaceLine: true, dayLabels: true, unit: nil)
        })
        let spend = try renderedHeight(ChartedBarBlock(chartHeight: 30, floor: nil) {
            DailyBarsChart(bars: bars, showsPaceLine: false, dayLabels: false, unit: .dollars)
        })
        #expect(week > 35)
        #expect(spend > 30)
    }

    // Noon keeps the calendar day stable under any machine time zone.
    private let bar = DayBar(
        day: chartDay(24, hour: 12), value: 4.2, heightFraction: 1, tint: .neutral, isToday: true, isFuture: false
    )

    @Test func dollarCaptionShowsDayAndTwoDecimalAmount() {
        #expect(DailyBarsChart.caption(for: bar, unit: .dollars) == "24 Oct · $4.20")
    }

    @Test func percentCaptionShowsOneDecimalShare() {
        let share = DayBar(
            day: bar.day, value: 0.4, heightFraction: 0.1, tint: .onPace, isToday: true, isFuture: false
        )
        #expect(DailyBarsChart.caption(for: share, unit: .percent) == "24 Oct · 0.4%")
    }

    @Test func weekCaptionReadsAsPercentOfTheLimit() {
        let day = DayBar(day: bar.day, value: 12, heightFraction: 0.4, tint: .onPace, isToday: false, isFuture: false)
        #expect(DailyBarsChart.caption(for: day, unit: nil) == "24 Oct · 12%")
    }

    @Test func captionForADayWithoutDataNamesOnlyTheDay() {
        let empty = DayBar(day: bar.day, value: nil, heightFraction: 0, tint: .neutral, isToday: false, isFuture: true)
        #expect(DailyBarsChart.caption(for: empty, unit: .dollars) == "24 Oct")
    }
}

import CoreGraphics
import Foundation
import Testing
@testable import UsageTracker

private let layoutCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/London")!
    return calendar
}()

private func at(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 11) -> Date {
    layoutCalendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}

// 3 November 2026 is a Tuesday; 10 November is the next one.
private let tuesday = 3

private func sample(_ date: Date, _ percent: UInt8) -> UsageSample {
    UsageSample(date: date, percent: percent)
}

private func window(resetsAt: Date, length: TimeInterval? = 7 * 86_400) -> LimitWindow {
    LimitWindow(id: "week", label: "Week", percentUsed: 0, resetsAt: resetsAt, parentID: nil, windowLength: length)
}

@Suite struct UsageChartLayoutTests {
    let size = CGSize(width: 200, height: 40)

    @Test func aSessionLineBreaksAcrossAGap() {
        let morning = (0...60).map { sample(at(5, 8, 0).addingTimeInterval(Double($0) * 60), 10) }
        let evening = (0...60).map { sample(at(5, 17, 0).addingTimeInterval(Double($0) * 60), 20) }

        let segments = UsageChartLayout.sessionSegments(
            samples: morning + evening, now: at(5, 18, 30), gap: 600, size: size
        )

        #expect(segments.count == 2)
        #expect(segments[0].count == 61)
    }

    @Test func aSessionLineNeedsTwoSamples() {
        let segments = UsageChartLayout.sessionSegments(
            samples: [sample(at(5, 8), 10)], now: at(5, 9), gap: 600, size: size
        )

        #expect(segments.isEmpty)
    }

    @Test func aSessionLineStaysInItsBox() {
        let samples = [sample(at(5, 8), 0), sample(at(5, 8, 5), 140), sample(at(5, 8, 10), 255)]

        let points = UsageChartLayout.sessionSegments(samples: samples, now: at(5, 9), gap: 600, size: size).flatMap { $0 }

        #expect(points.count == 3)
        #expect(points.allSatisfy { (0...size.width).contains($0.x) && (0...size.height).contains($0.y) })
        #expect(points[0].y == size.height)
        #expect(points[2].y == 0)
    }

    @Test func aSessionLinePlacesTimeAcrossTheSpan() {
        let now = at(5, 12)
        let samples = [sample(now.addingTimeInterval(-43_200), 50), sample(now, 50)]

        let points = UsageChartLayout.sessionSegments(samples: samples, now: now, gap: 50_000, size: size)[0]

        #expect(points[0].x == 100)
        #expect(points[1].x == 200)
        #expect(points[0].y == 20)
    }

    @Test func samplesOutsideTheSpanAreDropped() {
        let now = at(5, 12)
        let samples = [
            sample(now.addingTimeInterval(-90_000), 5),
            sample(now.addingTimeInterval(-86_400), 6),
            sample(now.addingTimeInterval(-120), 7),
            sample(now.addingTimeInterval(-60), 7),
            sample(now.addingTimeInterval(60), 8),
        ]

        let segments = UsageChartLayout.sessionSegments(samples: samples, now: now, gap: 200_000, size: size)

        #expect(segments.count == 1)
        #expect(segments[0].count == 2)
    }

    @Test func aResetDropsTheLine() {
        let samples = [sample(at(5, 8), 80), sample(at(5, 8, 1), 0)]

        let points = UsageChartLayout.sessionSegments(samples: samples, now: at(5, 9), gap: 600, size: size)[0]

        #expect(points[1].y == size.height)
    }

    @Test func sessionGapCoversTheInterval() {
        #expect(UsageChartLayout.sessionGap(interval: .thirtySeconds) == 600)
        #expect(UsageChartLayout.sessionGap(interval: .oneHour) == 7260)
    }

    @Test func weekDaysSplitAtMidnight() {
        let samples = [
            sample(at(tuesday, 10), 5), sample(at(tuesday, 23, 59), 12),
            sample(at(tuesday + 1, 23, 59), 30), sample(at(tuesday + 2, 12), 33),
        ]

        let days = UsageChartLayout.weekDays(
            samples: samples, window: window(resetsAt: at(tuesday + 7, 9)),
            assumedLength: 7 * 86_400, now: at(tuesday + 2, 12), calendar: layoutCalendar
        )

        #expect(days.count == 7)
        #expect(days[at(tuesday, 0)] == .some(12))
        #expect(days[at(tuesday + 1, 0)] == .some(18))
        #expect(days[at(tuesday + 2, 0)] == .some(3))
        for offset in 3...6 {
            #expect(days[at(tuesday + offset, 0)] == .some(nil))
        }
    }

    @Test func theResetMorningCountsTowardTheLastDay() {
        let samples = [
            sample(at(tuesday + 5, 23, 59), 58), sample(at(tuesday + 6, 23, 59), 64),
            sample(at(tuesday + 7, 8), 70),
        ]

        let days = UsageChartLayout.weekDays(
            samples: samples, window: window(resetsAt: at(tuesday + 7, 9)),
            assumedLength: 7 * 86_400, now: at(tuesday + 7, 8, 30), calendar: layoutCalendar
        )

        #expect(days.count == 7)
        #expect(days[at(tuesday + 6, 0)] == .some(12))
    }

    @Test func weekDaysBeforeHistoryAreEmpty() {
        // The window began Monday 2 November; the first sample is Wednesday.
        let samples = [sample(at(tuesday + 1, 10), 40), sample(at(tuesday + 1, 23, 59), 44)]

        let days = UsageChartLayout.weekDays(
            samples: samples, window: window(resetsAt: at(tuesday + 6, 9)),
            assumedLength: 7 * 86_400, now: at(tuesday + 2, 8), calendar: layoutCalendar
        )

        #expect(days[at(tuesday - 1, 0)] == .some(nil))
        #expect(days[at(tuesday, 0)] == .some(nil))
        #expect(days[at(tuesday + 1, 0)] == .some(4))
    }

    @Test func aQuietDayMidWeekIsEmpty() {
        // Samples Tuesday and Thursday, none on Wednesday.
        let samples = [
            sample(at(tuesday, 10), 5), sample(at(tuesday, 23), 12),
            sample(at(tuesday + 2, 9), 30), sample(at(tuesday + 2, 18), 36),
        ]

        let days = UsageChartLayout.weekDays(
            samples: samples, window: window(resetsAt: at(tuesday + 6, 9)),
            assumedLength: 7 * 86_400, now: at(tuesday + 3, 8), calendar: layoutCalendar
        )

        #expect(days[at(tuesday, 0)] == .some(7))
        #expect(days[at(tuesday + 1, 0)] == .some(nil))
        #expect(days[at(tuesday + 2, 0)] == .some(6))
    }

    @Test func weekDaysUseTheAssumedLengthWithoutOne() {
        let days = UsageChartLayout.weekDays(
            samples: [], window: window(resetsAt: at(tuesday + 7, 9), length: nil),
            assumedLength: 7 * 86_400, now: at(tuesday + 1, 8), calendar: layoutCalendar
        )

        #expect(days.count == 7)
    }

    @Test func dayBarsAgainstAShare() {
        let period = CyclePeriod(start: at(tuesday, 0), end: at(tuesday + 3, 0))
        let values: [Date: Double?] = [at(tuesday, 0): 12, at(tuesday + 1, 0): 18, at(tuesday + 2, 0): 30]

        let bars = UsageChartLayout.dayBars(
            values: values, period: period, share: 14.3, today: at(tuesday + 2, 12), calendar: layoutCalendar
        )

        #expect(bars.map(\.heightFraction) == [12 / 28.6, 18 / 28.6, 1])
        #expect(bars.map(\.tint) == [.onPace, .overBudget, .overBudget])
    }

    @Test func dayBarsWithoutAShareScaleToTheLargest() {
        let period = CyclePeriod(start: at(tuesday, 0), end: at(tuesday + 2, 0))
        let values: [Date: Double?] = [at(tuesday, 0): 2, at(tuesday + 1, 0): 4]

        let bars = UsageChartLayout.dayBars(
            values: values, period: period, share: nil, today: at(tuesday + 1, 12), calendar: layoutCalendar
        )

        #expect(bars.map(\.heightFraction) == [0.5, 1])
        #expect(bars.map(\.tint) == [.neutral, .neutral])
    }

    @Test func dayBarsMarkTodayAndFuture() {
        let period = CyclePeriod(start: at(tuesday, 0), end: at(tuesday + 3, 0))
        let values: [Date: Double?] = [at(tuesday, 0): 5, at(tuesday + 1, 0): 7, at(tuesday + 2, 0): nil]

        let bars = UsageChartLayout.dayBars(
            values: values, period: period, share: 10, today: at(tuesday + 1, 12), calendar: layoutCalendar
        )

        #expect(bars.map(\.isToday) == [false, true, false])
        #expect(bars.map(\.isFuture) == [false, false, true])
        #expect(bars[2].value == nil)
        #expect(bars[2].heightFraction == 0)
        #expect(bars[2].tint == .neutral)
        #expect(bars[1].value == 7)
    }

    @Test func spendValuesFillPastDaysWithZero() {
        let period = CyclePeriod(start: at(tuesday, 0), end: at(tuesday + 4, 0))
        let spend = [DaySpend(day: at(tuesday + 1, 0), amount: 3.5)]

        let values = UsageChartLayout.spendValues(
            spend, period: period, today: at(tuesday + 2, 12), calendar: layoutCalendar
        )

        #expect(values[at(tuesday, 0)] == .some(0))
        #expect(values[at(tuesday + 1, 0)] == .some(3.5))
        #expect(values[at(tuesday + 2, 0)] == .some(0))
        #expect(values[at(tuesday + 3, 0)] == .some(nil))
    }

    @Test func aWeekAcrossTheAutumnClockChangeHasSevenLocalDays() {
        // Sunday 25 October 2026 has 25 hours; the window ends Tuesday 27th.
        let samples = [
            sample(at(23, 12, month: 10), 8), sample(at(24, 12, month: 10), 10),
            sample(at(25, 12, month: 10), 15), sample(at(25, 23, 30, month: 10), 20),
            sample(at(26, 20, month: 10), 26),
        ]

        let days = UsageChartLayout.weekDays(
            samples: samples, window: window(resetsAt: at(27, 9, month: 10)),
            assumedLength: 7 * 86_400, now: at(26, 20, 30, month: 10), calendar: layoutCalendar
        )

        #expect(Set(days.keys) == Set((20...26).map { at($0, 0, month: 10) }))
        #expect(days[at(24, 0, month: 10)] == .some(2))
        #expect(days[at(25, 0, month: 10)] == .some(10))
        #expect(days[at(26, 0, month: 10)] == .some(6))
    }

    @Test func aWeekAcrossTheSpringClockChangeHasSevenLocalDays() {
        // Sunday 29 March 2026 has 23 hours; the window ends Tuesday 31st.
        let samples = [
            sample(at(28, 12, month: 3), 10), sample(at(29, 12, month: 3), 16),
            sample(at(30, 12, month: 3), 20),
        ]

        let days = UsageChartLayout.weekDays(
            samples: samples, window: window(resetsAt: at(31, 9, month: 3)),
            assumedLength: 7 * 86_400, now: at(30, 13, month: 3), calendar: layoutCalendar
        )

        #expect(Set(days.keys) == Set((24...30).map { at($0, 0, month: 3) }))
        #expect(days[at(29, 0, month: 3)] == .some(6))
        #expect(days[at(30, 0, month: 3)] == .some(4))
    }

    @Test func aResetJustAfterMidnightStillStartsSevenDaysBack() {
        // 7 days before Monday 30 March 00:30 BST is 23 March by the calendar,
        // but 22 March 23:30 by seconds.
        let days = UsageChartLayout.weekDays(
            samples: [], window: window(resetsAt: at(30, 0, 30, month: 3)),
            assumedLength: 7 * 86_400, now: at(25, 12, month: 3), calendar: layoutCalendar
        )

        #expect(Set(days.keys) == Set((23...29).map { at($0, 0, month: 3) }))
    }

    @Test func weekDaysWithoutAResetAreEmpty() {
        let noReset = LimitWindow(id: "week", label: "Week", percentUsed: 0, resetsAt: nil, parentID: nil)

        let days = UsageChartLayout.weekDays(
            samples: [], window: noReset, assumedLength: 7 * 86_400, now: at(5, 12), calendar: layoutCalendar
        )

        #expect(days.isEmpty)
    }
}

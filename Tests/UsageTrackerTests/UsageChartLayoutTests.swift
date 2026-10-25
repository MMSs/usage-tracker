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

    private func slots(
        _ samples: [UsageSample], resetsAt: Date, now: Date, length: TimeInterval? = 7 * 86_400
    ) -> [UsageSlot] {
        UsageChartLayout.weekSlots(
            samples: samples, window: window(resetsAt: resetsAt, length: length),
            assumedLength: 7 * 86_400, now: now
        )
    }

    @Test func slotsStartAtTheReset() {
        let result = slots([], resetsAt: at(tuesday, 9), now: at(tuesday - 5, 12))

        #expect(result.count == 7)
        #expect(result.first?.start == at(tuesday - 7, 9))
        for (index, slot) in result.enumerated() {
            #expect(slot.start == at(tuesday - 7, 9).addingTimeInterval(Double(index) * 86_400))
            #expect(slot.end.timeIntervalSince(slot.start) == 86_400)
        }
    }

    @Test func slotsUseTheAssumedLengthWithoutOne() {
        #expect(slots([], resetsAt: at(tuesday + 7, 9), now: at(tuesday, 8), length: nil).count == 7)
    }

    @Test func slotsWithoutAResetAreEmpty() {
        let noReset = LimitWindow(id: "week", label: "Week", percentUsed: 0, resetsAt: nil, parentID: nil)

        let result = UsageChartLayout.weekSlots(
            samples: [], window: noReset, assumedLength: 7 * 86_400, now: at(5, 12)
        )

        #expect(result.isEmpty)
    }

    @Test func aSlotSpansTwoCalendarDays() {
        // The window began Tuesday 09:00.
        let samples = [
            sample(at(tuesday, 12), 4), sample(at(tuesday + 1, 8), 10), sample(at(tuesday + 2, 8, 59), 25),
        ]

        let result = slots(samples, resetsAt: at(tuesday + 7, 9), now: at(tuesday + 2, 8, 59))

        // Wednesday 08:00 belongs to the Tuesday slot and is Wednesday's base.
        #expect(result[0].value == 10)
        #expect(result[1].value == 15)
        #expect(result[2].value == nil)
    }

    @Test func theCurrentSlotRunsToNow() {
        let samples = [
            sample(at(tuesday, 12), 4), sample(at(tuesday + 1, 12), 10), sample(at(tuesday + 2, 10), 14),
            sample(at(tuesday + 2, 14), 20),
        ]

        let result = slots(samples, resetsAt: at(tuesday + 7, 9), now: at(tuesday + 2, 12))

        #expect(result.map(\.value) == [4, 6, 4, nil, nil, nil, nil])
    }

    @Test func anEmptySlotIsNilAndTheNextCountsFromItself() {
        // Nothing during the Wednesday slot; Thursday starts from its own first sample.
        let samples = [
            sample(at(tuesday, 10), 5), sample(at(tuesday, 20), 12),
            sample(at(tuesday + 2, 10), 30), sample(at(tuesday + 2, 18), 36),
        ]

        let result = slots(samples, resetsAt: at(tuesday + 7, 9), now: at(tuesday + 3, 8))

        #expect(result.map(\.value) == [12, nil, 6, nil, nil, nil, nil])
    }

    @Test func slotsBeforeHistoryAreEmpty() {
        let samples = [sample(at(tuesday + 2, 10), 40), sample(at(tuesday + 2, 20), 44)]

        let result = slots(samples, resetsAt: at(tuesday + 7, 9), now: at(tuesday + 3, 8))

        #expect(result.map(\.value) == [nil, nil, 4, nil, nil, nil, nil])
    }

    @Test func slotsAcrossAClockChange() {
        // Sunday 25 October 2026 has 25 hours; the window ends Tuesday 27th at 09:00.
        let samples = [
            sample(at(20, 12, month: 10), 2), sample(at(23, 12, month: 10), 8), sample(at(24, 12, month: 10), 10),
            sample(at(25, 12, month: 10), 15), sample(at(26, 12, month: 10), 26),
        ]

        let result = slots(samples, resetsAt: at(27, 9, month: 10), now: at(26, 13, month: 10))

        #expect(result.count == 7)
        #expect(result.allSatisfy { $0.end.timeIntervalSince($0.start) == 86_400 })
        let weekdays = result.map { layoutCalendar.component(.weekday, from: $0.start) }
        // 168 hours before Tuesday 09:00 GMT is Tuesday 10:00 BST; the weekdays run on from there.
        #expect(weekdays == [3, 4, 5, 6, 7, 1, 2])
        #expect(result.map(\.value) == [2, nil, nil, 0, 2, 5, 11])
    }

    @Test func slotBarsMarkTheCurrentSlot() {
        let samples = [sample(at(tuesday, 10), 5), sample(at(tuesday + 1, 8), 30), sample(at(tuesday + 1, 12), 32)]
        let result = slots(samples, resetsAt: at(tuesday + 7, 9), now: at(tuesday + 1, 12))

        let bars = UsageChartLayout.slotBars(result, share: 100.0 / 7, now: at(tuesday + 1, 12))

        #expect(bars.map(\.day) == result.map(\.start))
        #expect(bars.map(\.isToday) == [false, true, false, false, false, false, false])
        #expect(bars.map(\.isFuture) == [false, false, true, true, true, true, true])
        #expect(bars[0].value == 30)
        #expect(bars[1].value == 2)
        #expect(bars[2].value == nil)
        #expect(bars[2].heightFraction == 0)
        #expect(bars[0].heightFraction == 1)
        #expect(bars[1].tint == .onPace)
        #expect(bars[0].tint == .overBudget)
    }

    @Test func slotBarsWithoutAShareScaleToTheLargest() {
        let result = [
            UsageSlot(start: at(tuesday, 9), end: at(tuesday + 1, 9), value: 2),
            UsageSlot(start: at(tuesday + 1, 9), end: at(tuesday + 2, 9), value: 4),
        ]

        let bars = UsageChartLayout.slotBars(result, share: nil, now: at(tuesday + 1, 12))

        #expect(bars.map(\.heightFraction) == [0.5, 1])
        #expect(bars.map(\.tint) == [.neutral, .neutral])
    }
}

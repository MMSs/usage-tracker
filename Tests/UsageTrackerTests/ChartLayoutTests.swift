import Foundation
import Testing
@testable import UsageTracker

private let chartCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
    return calendar
}()

private func chartDay(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
    chartCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

@Suite struct ChartLayoutTests {
    let period = CyclePeriod(start: chartDay(2026, 10, 1), end: chartDay(2026, 11, 1))   // 31 days
    let today = chartDay(2026, 10, 24)

    private func bars(_ days: [DaySpend]) -> [ChartBar] {
        ChartLayout.bars(days: days, period: period, today: today, calendar: chartCalendar)
    }

    @Test func oneBarPerPeriodDay() {
        #expect(bars([]).count == 31)
    }

    @Test func largestAmountFillsTheBar() {
        let result = bars([
            DaySpend(day: chartDay(2026, 10, 3), amount: 2),
            DaySpend(day: chartDay(2026, 10, 4), amount: 8),
            DaySpend(day: chartDay(2026, 10, 5), amount: 4),
        ])
        #expect(result[3].heightFraction == 1.0)
        #expect(result[2].heightFraction == 0.25)
        #expect(result[4].heightFraction == 0.5)
    }

    @Test func missingDaysAreZeroFilled() {
        let result = bars([DaySpend(day: chartDay(2026, 10, 4), amount: 5)])
        #expect(result[0].amount == 0)
        #expect(result[0].heightFraction == 0)
        #expect(result[3].amount == 5)
    }

    @Test func todayIsFlaggedExactlyOnce() {
        let result = bars([])
        #expect(result.filter(\.isToday).count == 1)
        #expect(result.first { $0.isToday }?.day == chartDay(2026, 10, 24))
    }

    @Test func daysAfterTodayAreFuture() {
        let result = bars([])
        for bar in result {
            let expected = bar.day > chartDay(2026, 10, 24)
            #expect(bar.isFuture == expected)
        }
        #expect(result.filter(\.isFuture).count == 7)
    }

    @Test func allZeroSpendGivesZeroFractionsWithoutNaN() {
        let result = bars([DaySpend(day: chartDay(2026, 10, 2), amount: 0)])
        #expect(result.allSatisfy { $0.heightFraction == 0 && !$0.heightFraction.isNaN })
    }

    @Test func barWidthSharesAvailableWidthBetweenBars() {
        #expect(ChartLayout.barWidth(count: 31, available: 268) >= 2)
        #expect(ChartLayout.barWidth(count: 0, available: 268) == 0)
    }

    @Test func barWidthNeverDropsBelowTwoPoints() {
        #expect(ChartLayout.barWidth(count: 31, available: 10) == 2)
    }

    @Test func dayNotAtMidnightLandsOnItsCalendarDay() {
        let result = bars([DaySpend(day: chartDay(2026, 10, 5, hour: 15), amount: 3)])
        #expect(result[4].amount == 3)
        #expect(result[4].day == chartDay(2026, 10, 5))
    }
}

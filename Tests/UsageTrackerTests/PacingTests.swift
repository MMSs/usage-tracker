import Foundation
import Testing
@testable import UsageTracker

private let pacingCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
    return calendar
}()

private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    pacingCalendar.date(from: DateComponents(year: year, month: month, day: day))!
}

@Suite struct PacingTests {
    let period = CyclePeriod(start: day(2026, 10, 12), end: day(2026, 11, 11))   // 30 days

    @Test func idealSpendCountsTodayAsElapsed() {
        let p = PacingCalculator.make(spent: 100, spentToday: 10, budget: 300, period: period, today: day(2026, 10, 24), calendar: pacingCalendar)!
        #expect(p.totalDays == 30)
        #expect(p.elapsedDays == 12)
        #expect(p.remainingDays == 18)
        #expect(p.idealSpend == 130)
        #expect(p.spent == 100)
        #expect(p.status == .onTrack(by: 30))
        #expect(abs(p.tickFraction - 13.0 / 30.0) < 0.0001)
    }

    @Test func overBudgetWhenSpentExceedsIdeal() {
        let p = PacingCalculator.make(spent: 150, spentToday: 10, budget: 300, period: period, today: day(2026, 10, 24), calendar: pacingCalendar)!
        #expect(p.status == .over(by: 20))
    }

    @Test func firstDayIdealIsOneDaysShareAndProjectsNothing() {
        let p = PacingCalculator.make(spent: 5, spentToday: 5, budget: 300, period: period, today: day(2026, 10, 12), calendar: pacingCalendar)!
        #expect(p.elapsedDays == 0)
        #expect(p.idealSpend == 10)
        #expect(p.status == .onTrack(by: 5))
        #expect(p.projectedSpend == nil)
        #expect(p.todayBudget == 10)
    }

    @Test func exactlyOnPaceSpenderIsOnTrackAllDay() {
        // Day 2 of 30 at 10 a day: by evening today's 10 is already spent.
        let p = PacingCalculator.make(spent: 20, spentToday: 10, budget: 300, period: period, today: day(2026, 10, 13), calendar: pacingCalendar)!
        #expect(p.idealSpend == 20)
        #expect(p.status == .onTrack(by: 0))
        #expect(PacingTint.forPacing(p) == .onPace)
    }

    @Test func lastDayStillHasOneRemainingDay() {
        let p = PacingCalculator.make(spent: 290, spentToday: 1, budget: 300, period: period, today: day(2026, 11, 10), calendar: pacingCalendar)!
        #expect(p.remainingDays == 1)
        #expect(p.todayBudget == 11)
    }

    @Test func todayOutsideThePeriodGivesNoPacing() {
        #expect(PacingCalculator.make(spent: 1, spentToday: 0, budget: 300, period: period, today: day(2026, 11, 11), calendar: pacingCalendar) == nil)
        #expect(PacingCalculator.make(spent: 1, spentToday: 0, budget: 300, period: period, today: day(2026, 10, 11), calendar: pacingCalendar) == nil)
    }

    @Test func zeroBudgetGivesNoPacing() {
        #expect(PacingCalculator.make(spent: 1, spentToday: 0, budget: 0, period: period, today: day(2026, 10, 24), calendar: pacingCalendar) == nil)
    }

    @Test func projectionUsesCompletedDays() {
        let p = PacingCalculator.make(spent: 130, spentToday: 10, budget: 300, period: period, today: day(2026, 10, 24), calendar: pacingCalendar)!
        #expect(p.projectedSpend == 300)
    }

    @Test func thirtyOneAndTwentyEightDayMonths() {
        let october = CyclePeriod(start: day(2026, 10, 1), end: day(2026, 11, 1))
        let february = CyclePeriod(start: day(2027, 2, 1), end: day(2027, 3, 1))
        let oct = PacingCalculator.make(spent: 0, spentToday: 0, budget: 300, period: october, today: day(2026, 10, 1), calendar: pacingCalendar)!
        let feb = PacingCalculator.make(spent: 0, spentToday: 0, budget: 300, period: february, today: day(2027, 2, 1), calendar: pacingCalendar)!
        #expect(oct.totalDays == 31)
        #expect(feb.totalDays == 28)
    }

    @Test func overrideBudgetWinsOverLimit() {
        let spend = SpendPeriod(
            period: period,
            spent: 80,
            limit: 200,
            unit: .dollars,
            daily: [DaySpend(day: day(2026, 10, 24), amount: 10)]
        )
        let p = PacingCalculator.make(spend, budgetOverride: 100, today: day(2026, 10, 24), calendar: pacingCalendar)!
        #expect(p.fillFraction == 0.8)
    }

    @Test func tintThresholds() {
        #expect(PacingTint.forRemaining(percentUsed: 41) == .onPace)
        #expect(PacingTint.forRemaining(percentUsed: 70) == .nearingLimit)
        #expect(PacingTint.forRemaining(percentUsed: 82) == .overBudget)

        // Budget 300 on day 10 of 30 gives an ideal spend of exactly 100.
        let nearing = PacingCalculator.make(spent: 110, spentToday: 0, budget: 300, period: period, today: day(2026, 10, 21), calendar: pacingCalendar)
        let over = PacingCalculator.make(spent: 120, spentToday: 0, budget: 300, period: period, today: day(2026, 10, 21), calendar: pacingCalendar)
        #expect(PacingTint.forPacing(nearing) == .nearingLimit)
        #expect(PacingTint.forPacing(over) == .overBudget)
        #expect(PacingTint.forPacing(nil) == .neutral)
    }
}

@Suite struct PacingTintForSpendTests {
    @Test func spendTintFollowsRatioToBudget() {
        #expect(PacingTint.forSpend(10, budget: 10) == .onPace)
        #expect(PacingTint.forSpend(11, budget: 10) == .nearingLimit)
        #expect(PacingTint.forSpend(Decimal(string: "11.5")!, budget: 10) == .nearingLimit)
        #expect(PacingTint.forSpend(12, budget: 10) == .overBudget)
        #expect(PacingTint.forSpend(0, budget: 0) == .onPace)
        #expect(PacingTint.forSpend(1, budget: 0) == .overBudget)
    }
}

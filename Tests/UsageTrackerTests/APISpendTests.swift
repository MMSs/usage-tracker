import Foundation
import Testing
@testable import UsageTracker

struct APISpendTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        return calendar
    }()

    private func local(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
    }

    @Test func spendIsTheSumOfTheDailySeries() {
        let month = CyclePeriod(start: local(10, 1), end: local(11, 1))
        let days = [
            CostDay(day: local(10, 1), dollars: Decimal(string: "12.345678")!),
            CostDay(day: local(10, 3), dollars: Decimal(string: "2.995")!),
        ]

        let report = APISpend.report(days: days, month: month, today: local(10, 24), calendar: calendar)

        #expect(report.planName == nil)
        #expect(report.windows.isEmpty)
        #expect(report.extras.isEmpty)
        #expect(report.spend == SpendPeriod(
            period: month,
            spent: Decimal(string: "15.340678")!,
            limit: nil,
            unit: .dollars,
            daily: [
                DaySpend(day: local(10, 1), amount: Decimal(string: "12.345678")!),
                DaySpend(day: local(10, 3), amount: Decimal(string: "2.995")!),
            ]
        ))
    }

    @Test func noDaysIsAZeroSpendMonth() {
        let month = CyclePeriod(start: local(10, 1), end: local(11, 1))

        let report = APISpend.report(days: [], month: month, today: local(10, 24), calendar: calendar)

        #expect(report.spend == SpendPeriod(period: month, spent: 0, limit: nil, unit: .dollars, daily: []))
    }

    @Test func bucketsAfterLocalTodayFoldIntoToday() {
        let month = CyclePeriod(start: local(10, 1), end: local(11, 1))
        // 24 Oct 20:00 in Los Angeles is already 25 Oct in UTC, so the Admin
        // API can have a bucket for a local day that has not started.
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 20))!
        let days = [
            CostDay(day: local(10, 23), dollars: 1),
            CostDay(day: local(10, 24), dollars: 2),
            CostDay(day: local(10, 25), dollars: Decimal(string: "0.5")!),
        ]

        let report = APISpend.report(days: days, month: month, today: today, calendar: calendar)

        #expect(report.spend?.daily == [
            DaySpend(day: local(10, 23), amount: 1),
            DaySpend(day: local(10, 24), amount: Decimal(string: "2.5")!),
        ])
        #expect(report.spend?.spent == Decimal(string: "3.5"))
    }

    @Test func futureBucketCreatesTodayWhenTodayHasNoEntry() {
        let month = CyclePeriod(start: local(10, 1), end: local(11, 1))
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 20))!
        let days = [
            CostDay(day: local(10, 22), dollars: 1),
            CostDay(day: local(10, 25), dollars: 4),
            CostDay(day: local(10, 26), dollars: 1),
        ]

        let report = APISpend.report(days: days, month: month, today: today, calendar: calendar)

        #expect(report.spend?.daily == [
            DaySpend(day: local(10, 22), amount: 1),
            DaySpend(day: local(10, 24), amount: 5),
        ])
        #expect(report.spend?.spent == 6)
    }

    @Test func monthIsTheUTCMonthContainingToday() throws {
        var minusFive = Calendar(identifier: .gregorian)
        minusFive.timeZone = TimeZone(secondsFromGMT: -5 * 3600)!
        // 31 Oct 23:30 at UTC-5 is 1 Nov 04:30 UTC.
        let today = minusFive.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 23, minute: 30))!

        let month = try APISpend.month(containing: today, calendar: minusFive)

        #expect(month.start == minusFive.date(from: DateComponents(year: 2026, month: 11, day: 1)))
        #expect(month.end == minusFive.date(from: DateComponents(year: 2026, month: 12, day: 1)))
    }

    @Test func decemberRollsIntoNextYear() throws {
        let month = try APISpend.month(containing: local(12, 15), calendar: calendar)

        #expect(month.start == local(12, 1))
        #expect(month.end == calendar.date(from: DateComponents(year: 2027, month: 1, day: 1)))
    }
}

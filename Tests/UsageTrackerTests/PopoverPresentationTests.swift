import Foundation
import Testing
@testable import UsageTracker

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
    return calendar
}()

private func date(_ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}

private func pacing(status: PacingStatus, remainingDays: Int = 18) -> Pacing {
    Pacing(
        totalDays: 30, elapsedDays: 30 - remainingDays, remainingDays: remainingDays,
        idealSpend: 120, status: status, todayBudget: 10, leftForToday: 5,
        projectedSpend: nil, tickFraction: 0.4, fillFraction: 0.3
    )
}

@Suite struct PopoverPresentationTests {
    @Test func pillTextDollars() {
        #expect(PopoverPresentation.pillText(pacing(status: .onTrack(by: Decimal(string: "12.4")!)), unit: .dollars) == "On track by $12.40")
        #expect(PopoverPresentation.pillText(pacing(status: .over(by: Decimal(string: "3.1")!)), unit: .dollars) == "Over by $3.10")
    }

    @Test func pillTextPercent() {
        #expect(PopoverPresentation.pillText(pacing(status: .onTrack(by: Decimal(string: "4.2")!)), unit: .percent) == "On track by 4.2%")
    }

    @Test func daysLeft() {
        #expect(PopoverPresentation.daysLeftText(pacing(status: .onTrack(by: 0), remainingDays: 18)) == "18 days left")
        #expect(PopoverPresentation.daysLeftText(pacing(status: .onTrack(by: 0), remainingDays: 1)) == "1 day left")
    }

    @Test func updatedTextUses24HourClock() {
        #expect(PopoverPresentation.updatedText(date(10, 24, hour: 14, minute: 31), calendar: calendar) == "Updated 14:31")
        #expect(PopoverPresentation.updatedText(date(10, 24, hour: 9, minute: 5), calendar: calendar) == "Updated 09:05")
        #expect(PopoverPresentation.updatedText(nil, calendar: calendar) == "Updated —")
    }

    @Test func halfErrorMapping() {
        #expect(PopoverPresentation.halfErrorText(.error) == "Unable to refresh.")
        #expect(PopoverPresentation.halfErrorText(.expired) == "Credential expired — replace it in Settings")
        #expect(PopoverPresentation.halfErrorText(.ready) == nil)
        #expect(PopoverPresentation.halfErrorText(.loading) == nil)
        #expect(PopoverPresentation.halfErrorText(.unconfigured) == nil)
    }

    @Test func headerSubtitle() {
        let cycle = CyclePeriod(start: date(10, 12), end: date(11, 11))
        #expect(PopoverPresentation.headerSubtitle(cycle: cycle, planName: "Pro", calendar: calendar) == "12 Oct → 10 Nov")
        #expect(PopoverPresentation.headerSubtitle(cycle: nil, planName: "Pro", calendar: calendar) == "Pro")
        #expect(PopoverPresentation.headerSubtitle(cycle: nil, planName: nil, calendar: calendar) == nil)
    }
}

import Foundation
import Testing
@testable import UsageTracker

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
    return calendar
}()

private let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 10))!

@Suite struct CountdownFormatterTests {
    @Test func compactUnderADay() {
        #expect(CountdownFormatter.compact(until: now + 2 * 3600 + 10 * 60, now: now) == "2h10")
        #expect(CountdownFormatter.compact(until: now + 2 * 3600 + 5 * 60, now: now) == "2h05")
        #expect(CountdownFormatter.compact(until: now + 45 * 60, now: now) == "45m")
        #expect(CountdownFormatter.compact(until: now + 30, now: now) == "<1m")
    }

    @Test func compactDaysRoundDown() {
        #expect(CountdownFormatter.compact(until: now + 3 * 86400 + 20 * 3600, now: now) == "3d")
        #expect(CountdownFormatter.compact(until: now + 86400, now: now) == "1d")
    }

    @Test func compactPastIsZero() {
        #expect(CountdownFormatter.compact(until: now - 60, now: now) == "0m")
    }

    @Test(arguments: [
        (Locale.HourCycle.zeroToTwentyThree, true),
        (.oneToTwentyFour, true),
        (.oneToTwelve, false),
        (.zeroToEleven, false),
    ])
    func hourCycleDecidesTwelveOrTwentyFourHour(cycle: Locale.HourCycle, is24Hour: Bool) {
        #expect(CountdownFormatter.uses24Hour(hourCycle: cycle) == is24Hour)
    }

    private func date(
        _ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10, in calendar: Calendar = calendar
    ) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func text(
        _ resetsAt: Date?, from now: Date = now, _ style: CountdownFormatter.ResetStyle = .long,
        in calendar: Calendar = calendar, uses24Hour: Bool = false
    ) -> String? {
        CountdownFormatter.resetText(resetsAt: resetsAt, now: now, style: style, calendar: calendar, uses24Hour: uses24Hour)
    }

    @Test func sessionResetTodayShowsOnlyTheTime() {
        let evening = date(24, 20, 27)
        #expect(text(date(24, 23), from: evening, .session) == "resets in 2h 33m · 11:00pm")
        #expect(text(date(24, 23), from: evening, .session, uses24Hour: true) == "resets in 2h 33m · 23:00")
        #expect(text(date(24, 11, 30), .session) == "resets in 1h 30m · 11:30am")
    }

    @Test func sessionResetNextCalendarDayNamesTomorrow() {
        let evening = date(24, 20, 50)
        #expect(text(date(25, 1), from: evening, .session) == "resets in 4h 10m · tomorrow 1:00am")
        #expect(text(date(25, 1), from: evening, .session, uses24Hour: true) == "resets in 4h 10m · tomorrow 01:00")
    }

    @Test func longResetTodayNamesToday() {
        let early = date(24, 4, 55)
        #expect(text(date(24, 8), from: early) == "resets in 3h 5m · today 8:00am")
        #expect(text(date(24, 8), from: early, uses24Hour: true) == "resets in 3h 5m · today 08:00")
    }

    @Test func longResetTomorrowNamesTomorrow() {
        let morning = date(24, 6, 55)
        #expect(text(date(25, 8), from: morning) == "resets in 1d 2h · tomorrow 8:00am")
    }

    @Test func longResetWithinAWeekNamesTheWeekday() {
        let morning = date(24, 23)
        #expect(text(date(27, 8), from: morning) == "resets in 2d 10h · Tue 8:00am")
        #expect(text(date(27, 15, 5), from: morning, uses24Hour: true) == "resets in 2d 17h · Tue 15:05")
        #expect(text(date(30, 9)) == "resets in 6d · Fri 9:00am")
    }

    @Test func longResetBeyondAWeekShowsTheDateAndTime() {
        let evening = date(22, 20)
        #expect(text(date(3, 8, month: 11), from: evening) == "resets in 11d · 3 Nov 8:00am")
        #expect(text(date(11, 0, month: 11)) == "resets in 17d · 11 Nov 12:00am")
        #expect(text(now + 7 * 86400) == "resets in 7d · 31 Oct 9:00am")
        #expect(text(now + 7 * 86400, uses24Hour: true) == "resets in 7d · 31 Oct 09:00")
    }

    @Test func resetAtMidnightBelongsToTheNextDay() {
        let evening = date(24, 22)
        #expect(text(date(25, 0), from: evening, .session) == "resets in 2h · tomorrow 12:00am")
        #expect(text(date(25, 0), from: evening, .session, uses24Hour: true) == "resets in 2h · tomorrow 00:00")
        #expect(text(date(24, 23, 59), from: evening, .session) == "resets in 1h 59m · 11:59pm")
        #expect(text(date(25, 0), from: evening) == "resets in 2h · tomorrow 12:00am")
    }

    @Test func resetAcrossAClockChangeUsesRealElapsedTimeAndCalendarDays() {
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!

        // Clocks go back at 03:00 on 25 Oct, so 00:30 to 08:00 spans 8h 30m.
        let night = date(25, 0, 30, in: berlin)
        #expect(text(date(25, 8, in: berlin), from: night, in: berlin) == "resets in 8h 30m · today 8:00am")
        #expect(text(date(25, 8, in: berlin), from: night, .session, in: berlin) == "resets in 8h 30m · 8:00am")

        // The extra hour lands in the countdown; the day is still two calendar days on.
        let saturday = date(24, 10, in: berlin)
        #expect(text(date(26, 8, in: berlin), from: saturday, in: berlin) == "resets in 1d 23h · Mon 8:00am")

        // 25 Oct is 25 hours long, so a reset a calendar day ahead is 25 hours away.
        #expect(text(date(26, 0, 30, in: berlin), from: night, .session, in: berlin) == "resets in 1d 1h · tomorrow 12:30am")
    }

    @Test func resetTextEdges() {
        #expect(text(now - 60) == "resets now")
        #expect(text(now) == "resets now")
        #expect(text(nil) == nil)
        #expect(text(now + 30, .session) == "resets in <1m · 10:00am")
        #expect(text(now + 45 * 60) == "resets in 45m · today 10:45am")
        #expect(text(now + 2 * 3600) == "resets in 2h · today 12:00pm")
    }
}

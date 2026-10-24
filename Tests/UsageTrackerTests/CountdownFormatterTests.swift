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

    @Test func resetTextRelativeUnderADayAbsoluteAfter() {
        #expect(CountdownFormatter.resetText(resetsAt: now + 2 * 3600 + 10 * 60, now: now, calendar: calendar) == "resets in 2h 10m")
        #expect(CountdownFormatter.resetText(resetsAt: now + 2 * 3600, now: now, calendar: calendar) == "resets in 2h")
        #expect(CountdownFormatter.resetText(resetsAt: now + 45 * 60, now: now, calendar: calendar) == "resets in 45m")

        let tuesday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 9))!
        #expect(CountdownFormatter.resetText(resetsAt: tuesday, now: now, calendar: calendar) == "resets Tue 09:00")
        let afternoon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 15, minute: 5))!
        #expect(CountdownFormatter.resetText(resetsAt: afternoon, now: now, calendar: calendar) == "resets Tue 15:05")
        #expect(CountdownFormatter.resetText(resetsAt: now - 60, now: now, calendar: calendar) == "resets now")
        #expect(CountdownFormatter.resetText(resetsAt: nil, now: now, calendar: calendar) == nil)
    }
}

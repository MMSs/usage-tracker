import Foundation

enum CountdownFormatter {
    private static let minute: TimeInterval = 60
    private static let hour: TimeInterval = 3600
    private static let day: TimeInterval = 86400

    /// "2h10", "45m", "<1m" or "3d"; a date in the past reads "0m".
    static func compact(until date: Date, now: Date) -> String {
        let interval = date.timeIntervalSince(now)

        guard interval > 0 else {
            return "0m"
        }

        if interval < minute {
            return "<1m"
        }

        if interval < hour {
            return "\(Int(interval / minute))m"
        }

        if interval < day {
            let hours = Int(interval / hour)
            let minutes = Int(interval.truncatingRemainder(dividingBy: hour) / minute)
            return "\(hours)h" + (minutes < 10 ? "0" : "") + "\(minutes)"
        }

        return "\(Int(interval / day))d"
    }

    /// Which exact-time wording a popover reset uses.
    enum ResetStyle {
        /// The short window (the session): just the time, with "tomorrow" past midnight.
        case session
        /// Longer windows: "today", "tomorrow", a weekday within a week, else the date.
        case long
    }

    /// Whether the system clock is set to 24-hour time.
    static var systemUses24Hour: Bool {
        uses24Hour(hourCycle: Locale.autoupdatingCurrent.hourCycle)
    }

    static func uses24Hour(hourCycle: Locale.HourCycle) -> Bool {
        switch hourCycle {
        case .oneToTwelve, .zeroToEleven: false
        case .zeroToTwentyThree, .oneToTwentyFour: true
        @unknown default: true
        }
    }

    /// The countdown with the exact time after it, e.g. "resets in 2h 33m · 11:00pm"
    /// for a session or "resets in 2d 10h · Tue 8:00am" for a longer window.
    static func resetText(
        resetsAt: Date?,
        now: Date,
        style: ResetStyle = .long,
        calendar: Calendar = .current,
        uses24Hour: Bool = systemUses24Hour
    ) -> String? {
        guard let resetsAt else {
            return nil
        }

        let interval = resetsAt.timeIntervalSince(now)

        if interval <= 0 {
            return "resets now"
        }

        let exact = exactTime(resetsAt, now: now, style: style, calendar: calendar, uses24Hour: uses24Hour)
        return "resets in " + relative(interval) + " · " + exact
    }

    private static func relative(_ interval: TimeInterval) -> String {
        if interval < minute {
            return "<1m"
        }

        if interval >= 7 * day {
            return "\(Int(interval / day))d"
        }

        let days = Int(interval / day)
        let hours = Int(interval.truncatingRemainder(dividingBy: day) / hour)
        let minutes = Int(interval.truncatingRemainder(dividingBy: hour) / minute)

        // Under a day the minutes matter; from a day up they are noise.
        let parts = days > 0
            ? ["\(days)d", hours > 0 ? "\(hours)h" : nil]
            : [hours > 0 ? "\(hours)h" : nil, minutes > 0 ? "\(minutes)m" : nil]
        return parts.compactMap { $0 }.joined(separator: " ")
    }

    /// "2:31pm" or "14:31"; with `now`, "25 Oct, 12:30am" when `date` is not on `now`'s day.
    static func clockTime(
        _ date: Date,
        now: Date? = nil,
        calendar: Calendar = .current,
        uses24Hour: Bool = systemUses24Hour
    ) -> String {
        let formatter = formatter(calendar: calendar)
        formatter.dateFormat = uses24Hour ? "HH:mm" : "h:mma"
        let time = formatter.string(from: date)

        guard let now, !calendar.isDate(date, inSameDayAs: now) else {
            return time
        }

        formatter.dateFormat = "d MMM"
        return formatter.string(from: date) + ", " + time
    }

    /// English month and weekday names whatever the system language, with am/pm in lower case.
    private static func formatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        return formatter
    }

    private static func exactTime(
        _ date: Date, now: Date, style: ResetStyle, calendar: Calendar, uses24Hour: Bool
    ) -> String {
        let formatter = formatter(calendar: calendar)

        func string(_ format: String) -> String {
            formatter.dateFormat = format
            return formatter.string(from: date)
        }

        let time = string(uses24Hour ? "HH:mm" : "h:mma")
        let dayOffset = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)
        ).day ?? 0

        switch (style, dayOffset) {
        case (.session, 0):
            return time
        case (.session, 1), (.long, 1):
            return "tomorrow " + time
        case (.long, 0):
            return "today " + time
        case (_, 2..<7):
            return string("EEE") + " " + time
        default:
            return string("d MMM") + " " + time
        }
    }
}

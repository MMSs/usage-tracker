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

    /// "resets in 2h 10m" within a day, "resets Tue 09:00" beyond.
    static func resetText(resetsAt: Date?, now: Date, calendar: Calendar = .current) -> String? {
        guard let resetsAt else {
            return nil
        }

        let interval = resetsAt.timeIntervalSince(now)

        if interval < day {
            guard interval >= minute else {
                return "resets in <1m"
            }

            let hours = Int(interval / hour)
            let minutes = Int(interval.truncatingRemainder(dividingBy: hour) / minute)
            let parts = [hours > 0 ? "\(hours)h" : nil, minutes > 0 ? "\(minutes)m" : nil]
            return "resets in " + parts.compactMap { $0 }.joined(separator: " ")
        }

        let weekday = resetsAt.formatted(style(calendar).weekday(.abbreviated))
        let time = resetsAt.formatted(style(calendar).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        return "resets \(weekday) \(time)"
    }

    private static func style(_ calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(
            date: .omitted,
            time: .omitted,
            locale: Locale(identifier: "en_US_POSIX"),
            calendar: calendar,
            timeZone: calendar.timeZone
        )
    }
}

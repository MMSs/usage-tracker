import CoreGraphics
import Foundation

struct DayBar: Equatable {
    let day: Date
    /// Nil when there is no data for the day.
    let value: Double?
    /// Share of the bar's full height, 0...1.
    let heightFraction: Double
    let tint: PacingTint
    let isToday: Bool
    let isFuture: Bool
}

/// Turns usage samples and daily series into session lines and day bars.
enum UsageChartLayout {
    /// The session line always shows the last day.
    static let sessionSpan: TimeInterval = 86_400

    private static let day: TimeInterval = 86_400

    /// Polylines for the last `sessionSpan` of samples, one per run of samples
    /// no further than `gap` apart, so time without samples draws empty.
    static func sessionSegments(
        samples: [UsageSample],
        now: Date,
        gap: TimeInterval,
        size: CGSize
    ) -> [[CGPoint]] {
        let visible = samples
            .filter { $0.date <= now && now.timeIntervalSince($0.date) < sessionSpan }
            .sorted { $0.date < $1.date }
        guard visible.count >= 2 else { return [] }

        var runs: [[UsageSample]] = []
        for sample in visible {
            if let last = runs.last?.last, sample.date.timeIntervalSince(last.date) <= gap {
                runs[runs.count - 1].append(sample)
            } else {
                runs.append([sample])
            }
        }

        return runs.filter { $0.count >= 2 }.map { run in
            run.map { sample in
                CGPoint(
                    x: size.width * (1 - now.timeIntervalSince(sample.date) / sessionSpan),
                    y: size.height * (1 - Double(min(sample.percent, 100)) / 100)
                )
            }
        }
    }

    /// The longest pause between samples that still counts as one line: two
    /// refresh intervals and a minute, and never under ten minutes.
    static func sessionGap(interval: RefreshInterval) -> TimeInterval {
        max(600, 2 * TimeInterval(interval.seconds) + 60)
    }

    /// Percent used per calendar day of a limit window, keyed by start of day.
    /// A day's value is its rise over the day; nil means no data (a past day
    /// without samples, or after today).
    static func weekDays(
        samples: [UsageSample],
        window: LimitWindow,
        assumedLength: TimeInterval,
        now: Date,
        calendar: Calendar
    ) -> [Date: Double?] {
        guard let resetsAt = window.resetsAt else { return [:] }

        let length = window.windowLength ?? assumedLength
        let count = max(1, Int((length / day).rounded(.up)))
        // Whole days step by the calendar, so a clock change cannot shift the
        // start across midnight.
        let start = length.truncatingRemainder(dividingBy: day) == 0
            ? calendar.date(byAdding: .day, value: -count, to: resetsAt) ?? resetsAt.addingTimeInterval(-length)
            : resetsAt.addingTimeInterval(-length)
        let firstDay = calendar.startOfDay(for: start)

        let inWindow = samples
            .filter { $0.date >= start && $0.date <= resetsAt && $0.date <= now }
            .sorted { $0.date < $1.date }

        var result: [Date: Double?] = [:]
        for offset in 0..<count {
            guard let dayStart = calendar.date(byAdding: .day, value: offset, to: firstDay) else { break }

            guard dayStart <= now else {
                result.updateValue(nil, forKey: dayStart)
                continue
            }

            // The last day also takes the morning of the reset day.
            let isLast = offset == count - 1
            let dayEnd = isLast
                ? Date.distantFuture
                : calendar.date(byAdding: .day, value: 1, to: dayStart) ?? .distantFuture

            let previousStart = calendar.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart
            let previous = inWindow.last { $0.date >= previousStart && $0.date < dayStart }
            let during = inWindow.filter { $0.date >= dayStart && $0.date < dayEnd }

            guard let end = during.last else {
                // Today rose by nothing yet once history began; a past quiet day has no data.
                let isToday = now < dayEnd
                let began = inWindow.contains { $0.date < dayStart }
                result.updateValue(isToday && began ? 0 : nil, forKey: dayStart)
                continue
            }

            // Overnight usage counts toward the waking day, but only from a
            // sample the day before: after a gap the day counts from its own.
            let base = previous.map { Double($0.percent) }
                ?? (dayStart <= start ? 0 : Double(during[0].percent))
            result.updateValue(max(Double(end.percent) - base, 0), forKey: dayStart)
        }

        return result
    }

    /// One bar per day of `period`. With a `share` (the even daily share) a bar
    /// is tinted by how it compares and full at twice the share; without one,
    /// bars scale to the largest and stay neutral.
    static func dayBars(
        values: [Date: Double?],
        period: CyclePeriod,
        share: Double?,
        today: Date,
        calendar: Calendar
    ) -> [DayBar] {
        let startOfToday = calendar.startOfDay(for: today)
        let end = calendar.startOfDay(for: period.end)

        var days: [(day: Date, value: Double?)] = []
        var current = calendar.startOfDay(for: period.start)
        while current < end {
            let value = current > startOfToday ? nil : (values[current] ?? nil)
            days.append((current, value))
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        let largest = days.compactMap(\.value).max() ?? 0

        return days.map { entry in
            let height: Double
            let tint: PacingTint
            if let value = entry.value {
                if let share {
                    height = share > 0 ? min(value / (2 * share), 1) : (value > 0 ? 1 : 0)
                    tint = PacingTint.forSpend(Decimal(value), budget: Decimal(share))
                } else {
                    height = largest > 0 ? min(value / largest, 1) : 0
                    tint = .neutral
                }
            } else {
                height = 0
                tint = .neutral
            }

            return DayBar(
                day: entry.day,
                value: entry.value,
                heightFraction: height,
                tint: tint,
                isToday: calendar.isDate(entry.day, inSameDayAs: today),
                isFuture: entry.day > startOfToday
            )
        }
    }

    /// A daily spend series keyed by start of day. The API leaves zero-spend
    /// days out, so past days without an entry are 0; future days are nil.
    static func spendValues(
        _ days: [DaySpend],
        period: CyclePeriod,
        today: Date,
        calendar: Calendar
    ) -> [Date: Double?] {
        var amounts: [Date: Double] = [:]
        for spend in days {
            amounts[calendar.startOfDay(for: spend.day)] = NSDecimalNumber(decimal: spend.amount).doubleValue
        }

        let startOfToday = calendar.startOfDay(for: today)
        let end = calendar.startOfDay(for: period.end)

        var result: [Date: Double?] = [:]
        var current = calendar.startOfDay(for: period.start)
        while current < end {
            result.updateValue(current > startOfToday ? nil : (amounts[current] ?? 0), forKey: current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        return result
    }
}

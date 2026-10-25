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

/// One 24-hour stretch of a limit window.
struct UsageSlot: Equatable {
    let start: Date
    let end: Date
    /// Nil when there is no data for the slot.
    let value: Double?
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

    /// Percent used per 24-hour slot of a limit window, from its start (the
    /// reset time minus its length). A slot's value is its rise over the slot;
    /// nil means no data (a past slot without samples, a slot before the first
    /// sample, or one after `now`).
    static func weekSlots(
        samples: [UsageSample],
        window: LimitWindow,
        assumedLength: TimeInterval,
        now: Date
    ) -> [UsageSlot] {
        guard let resetsAt = window.resetsAt else { return [] }

        let length = window.windowLength ?? assumedLength
        let count = max(1, Int((length / day).rounded(.up)))
        let start = resetsAt.addingTimeInterval(-length)

        let inWindow = samples
            .filter { $0.date >= start && $0.date <= resetsAt && $0.date <= now }
            .sorted { $0.date < $1.date }

        return (0..<count).map { offset in
            let slotStart = start.addingTimeInterval(Double(offset) * day)
            let slotEnd = slotStart.addingTimeInterval(day)

            guard slotStart <= now else {
                return UsageSlot(start: slotStart, end: slotEnd, value: nil)
            }

            let previous = inWindow.last { $0.date < slotStart }
            let during = inWindow.filter { $0.date >= slotStart && $0.date < slotEnd }

            guard let last = during.last else {
                // The current slot rose by nothing yet once history began; a past quiet slot has no data.
                let value: Double? = now < slotEnd && previous != nil ? 0 : nil
                return UsageSlot(start: slotStart, end: slotEnd, value: value)
            }

            // Overnight usage counts toward the waking slot, but only from a
            // sample in the slot before: after a gap the slot counts from its own.
            let base: Double
            if offset == 0 {
                base = 0
            } else if let previous, previous.date >= slotStart.addingTimeInterval(-day) {
                base = Double(previous.percent)
            } else {
                base = Double(during[0].percent)
            }

            return UsageSlot(start: slotStart, end: slotEnd, value: max(Double(last.percent) - base, 0))
        }
    }

    /// One bar per slot. With a `share` (the even slot share) a bar is tinted
    /// by how it compares and full at twice the share; without one, bars scale
    /// to the largest and stay neutral.
    static func slotBars(_ slots: [UsageSlot], share: Double?, now: Date) -> [DayBar] {
        let largest = slots.compactMap(\.value).max() ?? 0

        return slots.map { slot in
            DayBar(
                day: slot.start,
                value: slot.value,
                heightFraction: barHeight(slot.value, share: share, largest: largest),
                tint: barTint(slot.value, share: share),
                isToday: slot.start <= now && now < slot.end,
                isFuture: slot.start > now
            )
        }
    }

    private static func barHeight(_ value: Double?, share: Double?, largest: Double) -> Double {
        guard let value else { return 0 }
        if let share {
            return share > 0 ? min(value / (2 * share), 1) : (value > 0 ? 1 : 0)
        }
        return largest > 0 ? min(value / largest, 1) : 0
    }

    private static func barTint(_ value: Double?, share: Double?) -> PacingTint {
        guard let value, let share else { return .neutral }
        return PacingTint.forSpend(Decimal(value), budget: Decimal(share))
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
            return DayBar(
                day: entry.day,
                value: entry.value,
                heightFraction: barHeight(entry.value, share: share, largest: largest),
                tint: barTint(entry.value, share: share),
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

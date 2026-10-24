import CoreGraphics
import Foundation

struct ChartBar: Equatable, Identifiable {
    let day: Date
    let amount: Decimal
    /// Share of the period's largest amount, 0...1.
    let heightFraction: Double
    let isToday: Bool
    let isFuture: Bool

    var id: Date { day }
}

/// Turns a daily series into one bar per day of a cycle period.
enum ChartLayout {
    static func bars(
        days: [DaySpend],
        period: CyclePeriod,
        today: Date,
        calendar: Calendar = .current
    ) -> [ChartBar] {
        var amounts: [(day: Date, amount: Decimal)] = []
        var amountByDay: [Date: Decimal] = [:]
        for spend in days {
            amountByDay[calendar.startOfDay(for: spend.day)] = spend.amount
        }

        var day = calendar.startOfDay(for: period.start)
        let end = period.end
        let startOfToday = calendar.startOfDay(for: today)
        while day < end {
            amounts.append((day, amountByDay[day] ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        let largest = amounts.map(\.amount).max() ?? 0

        return amounts.map { entry in
            ChartBar(
                day: entry.day,
                amount: entry.amount,
                heightFraction: fraction(of: entry.amount, in: largest),
                isToday: calendar.isDate(entry.day, inSameDayAs: today),
                isFuture: entry.day > startOfToday
            )
        }
    }

    /// Width of one bar when `count` bars and their gaps share `available`.
    static func barWidth(count: Int, available: CGFloat, spacing: CGFloat = 2) -> CGFloat {
        guard count > 0 else { return 0 }

        return max(2, (available - spacing * CGFloat(count - 1)) / CGFloat(count))
    }

    private static func fraction(of amount: Decimal, in largest: Decimal) -> Double {
        guard largest > 0 else { return 0 }

        let ratio = NSDecimalNumber(decimal: amount / largest).doubleValue
        return min(max(ratio, 0), 1)
    }
}

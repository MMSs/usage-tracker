import Foundation

struct CostDay: Equatable, Sendable {
    /// Local midnight of the bucket's UTC calendar date.
    let day: Date
    /// Full precision; formatting rounds later.
    let dollars: Decimal

    /// The bucket's UTC calendar date, as local midnight.
    static func localDay(ofUTC date: Date, calendar: Calendar) throws -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!

        let parts = utc.dateComponents([.year, .month, .day], from: date)
        guard let day = calendar.date(from: parts) else {
            throw FetchError.decoding
        }

        return day
    }
}

enum APISpend {
    /// The Admin API buckets by UTC day, so the month is the UTC calendar
    /// month containing `today`; its bounds are local midnights of that
    /// month's first day and the next month's first day. `end` is exclusive.
    static func month(containing today: Date, calendar: Calendar) throws -> CyclePeriod {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!

        let parts = utc.dateComponents([.year, .month], from: today)
        guard let year = parts.year, let month = parts.month,
              let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let end = calendar.date(from: DateComponents(
                  year: month == 12 ? year + 1 : year,
                  month: month == 12 ? 1 : month + 1,
                  day: 1
              ))
        else {
            throw FetchError.decoding
        }

        return CyclePeriod(start: start, end: end)
    }

    /// The Admin API buckets by UTC day, so near the end of a local day the
    /// newest bucket can be a local day that has not started. Those amounts
    /// fold into today so the chart never plots the future.
    static func report(days: [CostDay], month: CyclePeriod, today: Date, calendar: Calendar) -> ProviderReport {
        let startOfToday = calendar.startOfDay(for: today)
        var totals: [Date: Decimal] = [:]
        for day in days {
            totals[min(day.day, startOfToday), default: 0] += day.dollars
        }

        let spend = SpendPeriod(
            period: month,
            spent: days.reduce(0) { $0 + $1.dollars },
            limit: nil,
            unit: .dollars,
            daily: totals.map { DaySpend(day: $0.key, amount: $0.value) }.sorted { $0.day < $1.day }
        )

        return ProviderReport(planName: nil, windows: [], extras: [], spend: spend)
    }
}

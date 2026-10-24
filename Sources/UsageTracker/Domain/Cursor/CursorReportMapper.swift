import Foundation

enum CursorReportMapper {
    static func map(
        usage: CursorUsageResponse,
        daily: DailySpendResponse?,
        today: Date,
        calendar: Calendar = .current
    ) -> ProviderReport {
        let period = CyclePeriod(
            start: dateInCalendar(forAPIDateOnly: usage.billingCycleStart, calendar: calendar),
            end: dateInCalendar(forAPIDateOnly: usage.billingCycleEnd, calendar: calendar)
        )
        let overall = usage.individualUsage.overall
        let usedDollars = Decimal(overall.used) / 100
        let cycleWindow = { (percent: Double) in
            LimitWindow(id: "cycle", label: "Included usage", percentUsed: percent, resetsAt: period.end, parentID: nil)
        }

        if usage.isUnlimited {
            return ProviderReport(
                planName: nil,
                windows: [],
                extras: [MoneyRow(id: "cycle", label: "Included usage", amount: usedDollars, limit: nil)],
                spend: SpendPeriod(
                    period: period,
                    spent: usedDollars,
                    limit: nil,
                    unit: .dollars,
                    daily: dollarSeries(daily, period: period, calendar: calendar)
                )
            )
        }

        if let limit = overall.limit {
            let limitDollars = Decimal(limit) / 100

            return ProviderReport(
                planName: nil,
                windows: [cycleWindow(Double(overall.used) / Double(limit) * 100)],
                extras: [MoneyRow(id: "cycle", label: "Included usage", amount: usedDollars, limit: limitDollars)],
                spend: SpendPeriod(
                    period: period,
                    spent: usedDollars,
                    limit: limitDollars,
                    unit: .dollars,
                    daily: dollarSeries(daily, period: period, calendar: calendar)
                )
            )
        }

        if let percent = overall.percentUsed {
            var windows = [cycleWindow(NSDecimalNumber(decimal: percent).doubleValue)]
            if let split = overall.percentSplit {
                windows.append(LimitWindow(
                    id: "auto", label: "Auto",
                    percentUsed: NSDecimalNumber(decimal: split.auto).doubleValue,
                    resetsAt: period.end, parentID: "cycle"
                ))
                windows.append(LimitWindow(
                    id: "api", label: "API models",
                    percentUsed: NSDecimalNumber(decimal: split.api).doubleValue,
                    resetsAt: period.end, parentID: "cycle"
                ))
            }

            return ProviderReport(
                planName: nil,
                windows: windows,
                extras: [],
                spend: SpendPeriod(
                    period: period,
                    spent: percent,
                    limit: 100,
                    unit: .percent,
                    daily: percentSeries(daily, cyclePercent: percent, period: period, calendar: calendar)
                )
            )
        }

        return ProviderReport(
            planName: nil,
            windows: [cycleWindow(0)],
            extras: [MoneyRow(id: "cycle", label: "Included usage", amount: usedDollars, limit: nil)],
            spend: SpendPeriod(
                period: period,
                spent: usedDollars,
                limit: nil,
                unit: .dollars,
                daily: dollarSeries(daily, period: period, calendar: calendar)
            )
        )
    }

    /// Every cycle day, zero-filled; `value` totals the entries for one day.
    private static func series(
        _ daily: DailySpendResponse?,
        period: CyclePeriod,
        calendar: Calendar,
        value: (_ dayEntries: [DailySpendResponse.Entry], _ allEntries: [DailySpendResponse.Entry]) -> Decimal
    ) -> [DaySpend] {
        guard let daily else {
            return []
        }

        var byDay: [Date: [DailySpendResponse.Entry]] = [:]
        for entry in daily.dailySpend {
            guard let milliseconds = Double(entry.day) else {
                continue
            }
            byDay[CursorDayConversion.localDay(forAPIMilliseconds: milliseconds, calendar: calendar), default: []].append(entry)
        }

        var result: [DaySpend] = []
        var day = period.start
        while day < period.end {
            result.append(DaySpend(day: day, amount: value(byDay[day] ?? [], daily.dailySpend)))
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }

        return result
    }

    private static func dollarSeries(_ daily: DailySpendResponse?, period: CyclePeriod, calendar: Calendar) -> [DaySpend] {
        series(daily, period: period, calendar: calendar) { entries, _ in
            Decimal(entries.reduce(0) { $0 + $1.spendCents }) / 100
        }
    }

    /// Cursor reports only tokens per day for percent plans, so a day's
    /// share of the cycle's percentage follows its share of the tokens.
    private static func percentSeries(
        _ daily: DailySpendResponse?,
        cyclePercent: Decimal,
        period: CyclePeriod,
        calendar: Calendar
    ) -> [DaySpend] {
        let tokens = { (entries: [DailySpendResponse.Entry]) in
            entries.reduce(0) { $0 + (Int($1.totalTokens ?? "") ?? 0) }
        }

        return series(daily, period: period, calendar: calendar) { entries, all in
            let cycleTokens = tokens(all)

            guard cycleTokens > 0 else {
                return 0
            }

            return cyclePercent * Decimal(tokens(entries)) / Decimal(cycleTokens)
        }
    }

    /// Cycle bounds are date-only in UTC; keep the same calendar day locally.
    private static func dateInCalendar(forAPIDateOnly date: Date, calendar: Calendar) -> Date {
        var apiCalendar = Calendar(identifier: .gregorian)
        apiCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = apiCalendar.dateComponents([.year, .month, .day], from: date)

        var local = Calendar(identifier: .gregorian)
        local.timeZone = calendar.timeZone

        return local.date(from: components)!
    }
}

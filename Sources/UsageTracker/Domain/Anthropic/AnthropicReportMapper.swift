import Foundation

enum AnthropicReportMapper {
    private static let sessionLength: TimeInterval = 5 * 3600
    private static let weeklyLength: TimeInterval = 7 * 86400
    private static let weeklyID = "weekly"

    static func subscription(_ snapshot: AnthropicSubscriptionSnapshot) -> ProviderReport {
        let usage = snapshot.usage
        var windows: [LimitWindow] = []

        if let fiveHour = usage.fiveHour {
            windows.append(LimitWindow(
                id: "session",
                label: "Session",
                percentUsed: fiveHour.utilization ?? 0,
                resetsAt: fiveHour.resetsAt,
                parentID: nil,
                windowLength: sessionLength
            ))
        }

        if let sevenDay = usage.sevenDay {
            windows.append(LimitWindow(
                id: weeklyID,
                label: "Weekly",
                percentUsed: sevenDay.utilization ?? 0,
                resetsAt: sevenDay.resetsAt,
                parentID: nil,
                windowLength: weeklyLength
            ))
            windows += modelWindows(usage)
        }

        var extras: [MoneyRow] = []
        if let spendLimit = snapshot.spendLimit, spendLimit.isEnabled {
            extras.append(MoneyRow(
                id: "overage",
                label: "Extra usage",
                amount: decimal(spendLimit.usedCredits),
                limit: decimal(spendLimit.monthlyCreditLimit)
            ))
        }

        if let creditGrant = snapshot.creditGrant {
            extras.append(MoneyRow(
                id: "credits",
                label: "Extra credits",
                amount: decimal(creditGrant.remainingBalance),
                limit: nil
            ))
        }

        return ProviderReport(planName: snapshot.planName, windows: windows, extras: extras, spend: nil)
    }

    /// The Admin API buckets by UTC day, so near the end of a local day the
    /// newest bucket can be a local day that has not started. Those amounts
    /// fold into today so the chart never plots the future.
    static func api(days: [AnthropicCostDay], month: CyclePeriod, today: Date, calendar: Calendar) -> ProviderReport {
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

    private static func modelWindows(_ usage: AnthropicUsageResponse) -> [LimitWindow] {
        let scopedLimits = usage.limits.filter { $0.kind == "weekly_scoped" }
        if !scopedLimits.isEmpty {
            return scopedLimits.compactMap { limit in
                guard let modelID = limit.modelID else { return nil }

                return LimitWindow(
                    id: "\(weeklyID):\(modelID)",
                    label: limit.modelDisplayName ?? modelID,
                    percentUsed: limit.percent ?? 0,
                    resetsAt: limit.resetsAt,
                    parentID: weeklyID,
                    windowLength: weeklyLength
                )
            }
        }

        // Older responses carry per-model windows as `seven_day_<suffix>`.
        // The dictionary has no order, so sort by suffix.
        return usage.legacyModelWindows
            .sorted { $0.key < $1.key }
            .compactMap { suffix, window in
                guard let utilization = window.utilization else { return nil }

                return LimitWindow(
                    id: "\(weeklyID):\(suffix)",
                    label: legacyLabel(suffix),
                    percentUsed: utilization,
                    resetsAt: window.resetsAt,
                    parentID: weeklyID,
                    windowLength: weeklyLength
                )
            }
    }

    private static func legacyLabel(_ suffix: String) -> String {
        let spaced = suffix.replacingOccurrences(of: "_", with: " ")

        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    /// Goes through the shortest decimal string so 12.34 stays 12.34 instead
    /// of the nearest binary fraction. Anything that is not a finite amount is 0.
    private static func decimal(_ value: Double) -> Decimal {
        guard value.isFinite else {
            return 0
        }

        let converted = Decimal(string: "\(value)") ?? Decimal(value)

        return converted.isFinite ? converted : 0
    }
}

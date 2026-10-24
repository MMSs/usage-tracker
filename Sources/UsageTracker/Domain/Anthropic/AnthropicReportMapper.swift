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
    /// of the nearest binary fraction.
    private static func decimal(_ value: Double) -> Decimal {
        Decimal(string: "\(value)") ?? Decimal(value)
    }
}

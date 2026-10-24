import Foundation

enum PopoverPresentation {
    static func pillText(_ pacing: Pacing, unit: BudgetUnit) -> String {
        switch pacing.status {
        case .onTrack(let by): "On track by \(unit.format(by))"
        case .over(let by): "Over by \(unit.format(by))"
        }
    }

    /// SF Symbol for the pacing pill: a check on pace, a warning that escalates with the tint.
    static func pillSymbol(_ tint: PacingTint) -> String {
        switch tint {
        case .onPace, .neutral: "checkmark.circle.fill"
        case .nearingLimit: "exclamationmark.circle.fill"
        case .overBudget: "exclamationmark.triangle.fill"
        }
    }

    /// "12 Oct → 11 Nov" for a cycle (the end is exclusive, so it shows the last day); otherwise the plan name.
    static func headerSubtitle(cycle: CyclePeriod?, planName: String?, calendar: Calendar = .current) -> String? {
        guard let cycle else {
            return planName
        }

        let lastDay = calendar.date(byAdding: .day, value: -1, to: cycle.end) ?? cycle.end
        return "\(dayMonth(cycle.start, calendar: calendar)) → \(dayMonth(lastDay, calendar: calendar))"
    }

    static func dayMonth(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    static func monthName(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "LLLL"
        return formatter.string(from: date)
    }

    /// A budget of zero or less is the same as no budget.
    static func effectiveBudget(_ budget: Decimal?) -> Decimal? {
        guard let budget, budget > 0 else {
            return nil
        }

        return budget
    }

    /// A window row's right-hand text: the matching money row's dollars in place
    /// of the percent when there is one, then days left or the reset time.
    static func rowText(window: LimitWindow, money: MoneyRow?, resetText: String?, daysLeft: String?) -> String {
        let value: String
        if let money {
            let amount = BudgetUnit.dollars.format(money.amount)
            value = money.limit.map { "\(amount) / \(BudgetUnit.dollars.format($0))" } ?? amount
        } else {
            value = "\(Int(window.percentUsed.rounded()))%"
        }

        guard let suffix = daysLeft ?? resetText else {
            return value
        }

        return value + " · " + suffix
    }

    /// A window row's bar fill; nil (no bar) when the row shows money with no limit to measure against.
    static func rowFraction(window: LimitWindow, money: MoneyRow?) -> Double? {
        if let money, money.limit == nil {
            return nil
        }

        return window.percentUsed / 100
    }

    static func daysLeftText(_ pacing: Pacing) -> String {
        pacing.remainingDays == 1 ? "1 day left" : "\(pacing.remainingDays) days left"
    }

    static func updatedText(_ date: Date?, calendar: Calendar = .current) -> String {
        guard let date else {
            return "Updated —"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return "Updated " + formatter.string(from: date)
    }

    static func halfErrorText(_ status: HalfStatus) -> String? {
        switch status {
        case .error: "Unable to refresh."
        case .expired: "Credential expired — replace it in Settings"
        case .unconfigured, .loading, .ready: nil
        }
    }
}

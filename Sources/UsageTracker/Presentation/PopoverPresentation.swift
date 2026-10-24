import Foundation

enum PopoverPresentation {
    static func pillText(_ pacing: Pacing, unit: BudgetUnit) -> String {
        switch pacing.status {
        case .onTrack(let by): "On track by \(unit.format(by))"
        case .over(let by): "Over by \(unit.format(by))"
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

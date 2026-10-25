import Foundation

/// What a window row draws over its bar.
enum ChartKind: Equatable {
    /// The session's last day of percent used.
    case sessionLine
    /// How much of the weekly limit each day used.
    case weekBars
    /// Each day's spend in the billing cycle.
    case cycleBars
}

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
            value = window.percentText
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

    /// A window row's ideal-time tick and tint: paced by elapsed time when the
    /// window has a length and is open, otherwise by how much of it is used.
    static func rowPacing(window: LimitWindow, now: Date) -> (tick: Double?, tint: PacingTint) {
        (TimePacing.idealFraction(for: window, now: now), PacingTint.forWindow(window, now: now))
    }

    /// The chart a top-level window row draws over its bar; nil for child rows
    /// and windows the descriptor does not name.
    static func chartKind(for window: LimitWindow, descriptor: ProviderDescriptor) -> ChartKind? {
        guard window.parentID == nil else {
            return nil
        }

        if window.id == descriptor.shortWindowID {
            return .sessionLine
        }

        guard window.id == descriptor.longWindowID else {
            return nil
        }

        return descriptor.capabilities.hasCycle ? .cycleBars : .weekBars
    }

    /// One bar per day of a weekly window, each against the even share of the
    /// limit; nil while no day has data.
    static func weekBars(samples: [UsageSample], window: LimitWindow, now: Date, calendar: Calendar = .current) -> [DayBar]? {
        let values = UsageChartLayout.weekDays(
            samples: samples, window: window, assumedLength: 7 * 86_400, now: now, calendar: calendar
        )
        guard values.values.contains(where: { $0 != nil }),
              let firstDay = values.keys.min(),
              let end = calendar.date(byAdding: .day, value: values.count, to: firstDay)
        else {
            return nil
        }

        return UsageChartLayout.dayBars(
            values: values,
            period: CyclePeriod(start: firstDay, end: end),
            share: 100 / Double(values.count),
            today: now,
            calendar: calendar
        )
    }

    /// One bar per day of a spend period, against `limit`'s even daily share
    /// when there is one.
    static func spendBars(_ spend: SpendPeriod, limit: Decimal?, today: Date, calendar: Calendar = .current) -> [DayBar] {
        let values = UsageChartLayout.spendValues(spend.daily, period: spend.period, today: today, calendar: calendar)
        let share = limit.flatMap { limit in
            values.isEmpty ? nil : NSDecimalNumber(decimal: limit).doubleValue / Double(values.count)
        }

        return UsageChartLayout.dayBars(values: values, period: spend.period, share: share, today: today, calendar: calendar)
    }

    /// The Projected tile's value: the amount alone, or a dash when there is no projection.
    static func projectedValue(_ pacing: Pacing, unit: BudgetUnit) -> String {
        pacing.projectedSpend.map(unit.format) ?? "—"
    }

    /// The Projected tile's caption, "by 31 Oct" (the end is exclusive, so it names the last day); nil with no projection.
    static func projectedCaption(_ pacing: Pacing, periodEnd: Date, calendar: Calendar = .current) -> String? {
        guard pacing.projectedSpend != nil else {
            return nil
        }

        let lastDay = calendar.date(byAdding: .day, value: -1, to: periodEnd) ?? periodEnd
        return "by " + dayMonth(lastDay, calendar: calendar)
    }

    static func daysLeftText(_ pacing: Pacing) -> String {
        pacing.remainingDays == 1 ? "1 day left" : "\(pacing.remainingDays) days left"
    }

    static func updatedText(
        _ date: Date?, calendar: Calendar = .current, uses24Hour: Bool = CountdownFormatter.systemUses24Hour
    ) -> String {
        guard let date else {
            return "Updated —"
        }

        return "Updated " + CountdownFormatter.clockTime(date, calendar: calendar, uses24Hour: uses24Hour)
    }

    /// "Last success 2:31pm", with the day when it was not today; nil with no success.
    static func lastSuccessText(
        _ date: Date?, now: Date, calendar: Calendar = .current, uses24Hour: Bool = CountdownFormatter.systemUses24Hour
    ) -> String? {
        guard let date else {
            return nil
        }

        return "Last success " + CountdownFormatter.clockTime(date, now: now, calendar: calendar, uses24Hour: uses24Hour)
    }

    /// What went wrong with a half and how to fix it; nil when nothing did.
    /// `display` is the half's menu bar display: a ready report it cannot
    /// draw shows there as an error, so it is explained here too.
    static func halfError(
        half: Half,
        status: HalfStatus,
        failure: RefreshFailure?,
        service: HalfService,
        display: HalfDisplay? = nil,
        now: Date = Date(),
        calendar: Calendar = .current,
        uses24Hour: Bool = CountdownFormatter.systemUses24Hour
    ) -> HalfErrorMessage? {
        let explanation: (text: String, fix: String?, severity: HalfErrorMessage.Severity)
        switch status {
        case .expired:
            explanation = failureExplanation(.unauthorized, service: service, now: now, calendar: calendar, uses24Hour: uses24Hour)
        case .error:
            explanation = failure.map { failureExplanation($0, service: service, now: now, calendar: calendar, uses24Hour: uses24Hour) }
                ?? ("Unable to refresh.", retries, .warning)
        case .needsOrganization:
            // Settings has the picker on the half's tab; "in Settings" would point at itself there.
            return HalfErrorMessage(
                text: "\(half.displayName): Choose an organization in Settings",
                fix: "The account belongs to more than one organization.",
                severity: .notice,
                settingsLine: "\(half.displayName): Choose an organization on the \(ProviderSettingsTab(half).title) tab."
            )
        case .ready where display == .status(.error), .loading where display == .status(.error):
            explanation = ("\(service.name) sent nothing the app can show.", mayHaveChanged, .warning)
        case .ready, .loading, .unconfigured:
            return nil
        }

        return HalfErrorMessage(
            text: "\(half.displayName): \(explanation.text)",
            fix: explanation.fix,
            severity: explanation.severity
        )
    }

    @MainActor
    static func halfError(
        _ model: HalfViewModel,
        descriptor: ProviderDescriptor,
        display: HalfDisplay?,
        now: Date = Date()
    ) -> HalfErrorMessage? {
        halfError(
            half: model.half,
            status: model.status,
            failure: model.lastFailure?.cause,
            service: descriptor.service(for: model.half),
            display: display,
            now: now
        )
    }

    private static let retries = "It retries automatically."
    private static let mayHaveChanged = "It may have changed; check for an update."

    private static func failureExplanation(
        _ failure: RefreshFailure,
        service: HalfService,
        now: Date,
        calendar: Calendar,
        uses24Hour: Bool
    ) -> (text: String, fix: String?, severity: HalfErrorMessage.Severity) {
        switch failure {
        case .transport, .offline:
            ("Couldn't reach \(service.host).", "Check your connection; it retries automatically.", .warning)
        case .challenge:
            ("\(service.host) asked for a browser check.", "Open \(service.host) in your browser, then Refresh.", .warning)
        case let .httpStatus(code):
            ("\(service.name) returned an error (HTTP \(code)).", retries, .warning)
        case let .rateLimited(until?) where until > now:
            ("\(service.name) is rate limiting requests; retrying at \(CountdownFormatter.clockTime(until, now: now, calendar: calendar, uses24Hour: uses24Hour)).", nil, .warning)
        case .rateLimited:
            // No time, or one already past: the next scheduled refresh asks.
            ("\(service.name) is rate limiting requests.", retries, .warning)
        case .decoding:
            ("\(service.name) sent a response the app doesn't understand.", mayHaveChanged, .warning)
        case .unauthorized:
            ("Credential expired — replace it in Settings", nil, .critical)
        case .keychain:
            ("Couldn't read the credential from Keychain.", "Unlock the login keychain and allow access if asked, then Refresh.", .warning)
        case .unexpected:
            ("Refreshing from \(service.name) failed unexpectedly.", retries, .warning)
        case .needsOrganization:
            // Its own status says so; this only shows if the status and cause ever disagree.
            ("Choose an organization in Settings", nil, .notice)
        }
    }
}

/// One half's error, as the popover row and the Settings status show it.
struct HalfErrorMessage: Equatable {
    enum Severity: Equatable {
        /// Something the user has to do, not a failure.
        case notice
        case warning, critical
    }

    /// Names the half: "Plan usage: Couldn't reach claude.ai."
    let text: String
    let fix: String?
    let severity: Severity
    /// The Settings status line, when it should differ from text and fix.
    var settingsLine: String? = nil

    /// The Settings status line: text and fix on one line unless `settingsLine` says otherwise.
    var line: String {
        settingsLine ?? [text, fix].compactMap { $0 }.joined(separator: " ")
    }
}

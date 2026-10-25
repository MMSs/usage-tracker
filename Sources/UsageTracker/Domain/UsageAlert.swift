import Foundation

struct UsageAlert: Equatable, Sendable {
    /// Identifies the alert for de-duplication: the measure's id plus the threshold.
    let key: String
    let title: String
    let body: String
}

/// One figure that can cross an alert threshold.
struct AlertMeasure: Equatable, Sendable {
    /// Stable for one window run or spend period, so a crossing alerts once.
    let id: String
    let percent: Double
    /// "Anthropic weekly · Fable".
    let subject: String
    let detail: String
}

/// What an alert is about. Each kind has its own switch under the master one.
enum AlertKind: String, CaseIterable, Sendable {
    case usage
    case session
    case failures

    var title: String {
        switch self {
        case .usage: "Usage thresholds"
        case .session: "Session"
        case .failures: "Refresh failures"
        }
    }

    var defaultEnabled: Bool {
        switch self {
        case .usage, .session: true
        case .failures: false
        }
    }
}

enum AlertPolicy {
    static let thresholds = [80, 95]

    /// The figures of one half that can alert: every open limit window, or
    /// (api half) spend against `budget`. Subscription spend belongs to its
    /// cycle window, so it is not measured on its own.
    static func measures(
        descriptor: ProviderDescriptor,
        half: Half,
        report: ProviderReport,
        budget: Decimal?,
        now: Date
    ) -> [AlertMeasure] {
        switch half {
        case .subscription:
            return report.windows.compactMap { windowMeasure($0, descriptor: descriptor, report: report, now: now) }
        case .api:
            return spendMeasure(descriptor: descriptor, report: report, budget: budget).map { [$0] } ?? []
        }
    }

    static func alert(for measure: AlertMeasure, threshold: Int) -> UsageAlert {
        UsageAlert(
            key: "\(measure.id).\(threshold)",
            title: "\(measure.subject) at \(Int(measure.percent.rounded(.down)))%",
            body: measure.detail
        )
    }

    /// One alert per ended session, keyed by the reset it ended at.
    static func sessionAlert(displayName: String, endedAt: Date, newSessionStarted: Bool, provider: Provider) -> UsageAlert {
        // Minutes absorb the sub-second jitter providers add to a reset.
        let minutes = Int((endedAt.timeIntervalSince1970 / 60).rounded())

        return UsageAlert(
            key: "\(provider.rawValue).session.\(minutes)",
            title: "\(displayName) session reset",
            body: newSessionStarted ? "New session started." : "You're back to 0%."
        )
    }

    /// Posted when a half starts failing; the key names the half, and the
    /// caller de-duplicates per streak.
    static func failureAlert(displayName: String, half: Half, cause: RefreshFailure, provider: Provider) -> UsageAlert {
        let text = cause.alertCause
        let name = switch half {
        case .subscription: "plan usage"
        case .api: "API spend"
        }

        return UsageAlert(
            key: "\(provider.rawValue).\(half.rawValue).failure",
            title: "\(displayName) \(name) couldn't refresh",
            body: text.prefix(1).uppercased() + text.dropFirst() + "."
        )
    }

    private static func windowMeasure(
        _ window: LimitWindow,
        descriptor: ProviderDescriptor,
        report: ProviderReport,
        now: Date
    ) -> AlertMeasure? {
        guard let resetsAt = window.resetsAt, window.percentUsed.isFinite else {
            return nil
        }

        let parent = window.parentID.flatMap { id in report.windows.first { $0.id == id } }
        var subject = "\(descriptor.displayName) \((parent ?? window).label.lowercased())"

        if parent != nil {
            subject += " · \(window.label)"
        }

        let style: CountdownFormatter.ResetStyle = window.id == descriptor.shortWindowID ? .session : .long
        let text = CountdownFormatter.resetText(resetsAt: resetsAt, now: now, style: style) ?? ""
        // Minutes absorb the sub-second jitter providers add to a reset.
        let minutes = Int((resetsAt.timeIntervalSince1970 / 60).rounded())

        return AlertMeasure(
            id: "\(descriptor.id.rawValue).\(window.id).\(minutes)",
            percent: window.percentUsed,
            subject: subject,
            detail: text.prefix(1).uppercased() + text.dropFirst() + "."
        )
    }

    private static func spendMeasure(
        descriptor: ProviderDescriptor,
        report: ProviderReport,
        budget: Decimal?
    ) -> AlertMeasure? {
        guard let spend = report.spend, let budget, budget > 0 else {
            return nil
        }

        let percent = NSDecimalNumber(decimal: spend.spent / budget * 100).doubleValue

        return AlertMeasure(
            id: "\(descriptor.id.rawValue).api.\(Int(spend.period.start.timeIntervalSince1970))",
            percent: percent,
            subject: "\(descriptor.displayName) API spend",
            detail: "\(BudgetUnit.dollars.format(spend.spent)) of \(BudgetUnit.dollars.format(budget)) budget this month."
        )
    }
}

enum SessionEnd {
    /// Resets that move by less than this are jitter, not a new session.
    private static let jitter: TimeInterval = 60

    /// `previousResetsAt` when the session last seen open with that reset has
    /// ended: its reset has passed, or the current window resets later than
    /// the jitter allows. Nil when there is no previous session.
    static func ended(previousResetsAt: Date?, current: LimitWindow?, now: Date) -> Date? {
        guard let previousResetsAt else {
            return nil
        }

        if now >= previousResetsAt {
            return previousResetsAt
        }

        if let reset = current?.resetsAt, reset.timeIntervalSince(previousResetsAt) > jitter {
            return previousResetsAt
        }

        return nil
    }
}

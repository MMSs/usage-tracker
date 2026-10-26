import Foundation

enum MenuBarStatus: Equatable {
    case setUp, expired, error, loading
    /// Drawn like `setUp`; VoiceOver says what to set up.
    case chooseOrganization

    var title: String {
        switch self {
        case .setUp, .chooseOrganization: "Set up"
        case .expired: "Expired"
        case .error: "Error"
        case .loading: "Loading"
        }
    }
}

struct MenuBarMeter: Equatable {
    let letter: String
    /// "41%", "73.50/200", "73.50/—" or "∞".
    let text: String
    let countdown: String?
    /// 0...1 fill; nil when unknown.
    let fraction: Double?
    let tick: Double?
    let tint: PacingTint
    let role: Role

    /// Which limit a meter measures; the Limits setting keeps meters by it.
    enum Role: Equatable, Sendable {
        case short, long, spend
    }

    /// What follows the letter: the value, the countdown, or both. A
    /// countdown-only line with no reset to count to reads "—".
    func lineText(showsValue: Bool, showsCountdown: Bool) -> String {
        switch (showsValue, showsCountdown ? countdown : nil) {
        case let (true, countdown?): "\(text) · \(countdown)"
        case (true, nil): text
        case let (false, countdown?): countdown
        case (false, nil): showsCountdown ? "—" : text
        }
    }
}

enum HalfDisplay: Equatable {
    case status(MenuBarStatus)
    case meters([MenuBarMeter], stale: Bool, errorMark: Bool)
    case money(text: String, meter: MenuBarMeter?, stale: Bool, errorMark: Bool)

    /// Expired, errored, or showing an old report after a failed refresh.
    var isFailure: Bool {
        switch self {
        case let .status(status): status == .expired || status == .error
        case let .meters(_, _, errorMark), let .money(_, _, _, errorMark): errorMark
        }
    }

    /// The failure alone, for a half the menu bar doesn't draw.
    fileprivate func failureText(half: Half) -> String {
        if case .status = self {
            return accessibilityText(half: half)
        }
        return "\(half.displayName): refresh failed"
    }

    /// Names `half` when it failed, so VoiceOver can tell which half the error mark is on.
    func accessibilityText(half: Half) -> String {
        let failed = "\(half.displayName): refresh failed"

        switch self {
        case .status(.error):
            return failed
        case .status(.expired):
            return "\(half.displayName): credential expired"
        case .status(.chooseOrganization):
            return "\(half.displayName): choose an organization"
        case let .status(status):
            return status.title
        case let .meters(meters, _, errorMark):
            let values = meters.filter { $0.text != "—" }.map { "\($0.letter) \($0.text)" }
            return (values + (errorMark ? [failed] : [])).joined(separator: ", ")
        case let .money(text, _, _, errorMark):
            return (["API \(text)"] + (errorMark ? [failed] : [])).joined(separator: ", ")
        }
    }
}

struct MenuBarItem: Equatable {
    let provider: Provider
    let subscription: HalfDisplay?
    let api: HalfDisplay?
    /// A half failed: the logo carries a "!" badge, even when that half is hidden.
    let logoBadge: Bool
    /// What VoiceOver says about failed halves the menu bar doesn't draw.
    let hiddenFailures: [String]

    init(
        provider: Provider,
        subscription: HalfDisplay?,
        api: HalfDisplay?,
        logoBadge: Bool = false,
        hiddenFailures: [String] = []
    ) {
        self.provider = provider
        self.subscription = subscription
        self.api = api
        self.logoBadge = logoBadge
        self.hiddenFailures = hiddenFailures
    }

    func accessibilityText(displayName: String) -> String {
        let halves = [
            subscription?.accessibilityText(half: .subscription),
            api?.accessibilityText(half: .api),
        ]
        return ([displayName] + halves.compactMap { $0 } + hiddenFailures).joined(separator: ", ")
    }
}

/// Which halves of a provider's item the menu bar draws.
struct MenuBarHalves: Equatable, Sendable {
    var subscription: Bool
    var api: Bool

    static let all = MenuBarHalves(subscription: true, api: true)
}

extension MenuBarItem {
    /// What the appearance and the provider's half switches let the item
    /// draw. With both halves hidden only the logo is left; a Limits choice
    /// with no matching meter keeps all. The set-up item, all there is to
    /// click while nothing is configured, is never hidden.
    func visible(in appearance: MenuBarAppearance, halves: MenuBarHalves) -> MenuBarItem {
        let setUp = HalfDisplay.status(.setUp)
        var subscription = halves.subscription || subscription == setUp ? subscription : nil
        let api = halves.api || api == setUp ? api : nil
        let hidden = [
            (Half.subscription, halves.subscription ? nil : self.subscription),
            (Half.api, halves.api ? nil : self.api),
        ].compactMap { half, display in
            display?.isFailure == true ? display?.failureText(half: half) : nil
        }

        if case let .meters(meters, stale, errorMark) = subscription, appearance.limits != .both {
            let role: MenuBarMeter.Role = appearance.limits == .short ? .short : .long
            let kept = meters.filter { $0.role == role }

            if !kept.isEmpty {
                subscription = .meters(kept, stale: stale, errorMark: errorMark)
            }
        }

        return MenuBarItem(provider: provider, subscription: subscription, api: api, logoBadge: logoBadge, hiddenFailures: hidden)
    }
}

struct HalfSnapshot {
    let status: HalfStatus
    let report: ProviderReport?
    let isStale: Bool

    init(status: HalfStatus, report: ProviderReport?, isStale: Bool) {
        self.status = status
        self.report = report
        self.isStale = isStale
    }

    @MainActor
    init(_ viewModel: HalfViewModel) {
        self.init(status: viewModel.status, report: viewModel.report, isStale: viewModel.isStale)
    }
}

enum MenuBarItemBuilder {
    /// nil when neither half has anything to show.
    static func make(
        descriptor: ProviderDescriptor,
        subscription: HalfSnapshot?,
        api: HalfSnapshot?,
        apiBudget: Decimal?,
        now: Date,
        calendar: Calendar = .current,
        forceSetUp: Bool = false
    ) -> MenuBarItem? {
        if forceSetUp {
            return MenuBarItem(provider: descriptor.id, subscription: .status(.setUp), api: nil)
        }

        let subscriptionDisplay = display(subscription) { report in
            subscriptionMeters(descriptor: descriptor, report: report, now: now, calendar: calendar)
        }
        let apiDisplay = display(api) { report in
            guard let spend = report.spend else {
                return nil
            }
            return .money(
                text: "$" + spendText(spend.spent),
                meter: apiMeter(spend: spend, text: "$" + spendText(spend.spent), budget: apiBudget, now: now, calendar: calendar)
            )
        }

        guard subscriptionDisplay != nil || apiDisplay != nil else {
            return nil
        }

        let failed = [subscriptionDisplay, apiDisplay].contains { $0?.isFailure == true }

        return MenuBarItem(provider: descriptor.id, subscription: subscriptionDisplay, api: apiDisplay, logoBadge: failed)
    }

    private enum Content {
        case meters([MenuBarMeter])
        case money(text: String, meter: MenuBarMeter?)
    }

    /// Maps one half's state to its display; `content` returns nil when the report holds nothing drawable.
    private static func display(_ snapshot: HalfSnapshot?, content: (ProviderReport) -> Content?) -> HalfDisplay? {
        guard let snapshot, snapshot.status != .unconfigured else {
            return nil
        }

        if snapshot.status == .expired {
            return .status(.expired)
        }

        // Nothing is fetched until the user chooses.
        if snapshot.status == .needsOrganization {
            return .status(.chooseOrganization)
        }

        guard let report = snapshot.report else {
            return .status(snapshot.status == .error ? .error : .loading)
        }

        guard let content = content(report) else {
            return .status(.error)
        }

        let errorMark = snapshot.status == .error
        // A failed refresh leaves the cached report on screen, dimmed like a stale one.
        let stale = snapshot.isStale || errorMark

        switch content {
        case let .meters(meters):
            return meters.isEmpty ? .status(.error) : .meters(meters, stale: stale, errorMark: errorMark)
        case let .money(text, meter):
            return .money(text: text, meter: meter, stale: stale, errorMark: errorMark)
        }
    }

    private static func subscriptionMeters(
        descriptor: ProviderDescriptor,
        report: ProviderReport,
        now: Date,
        calendar: Calendar
    ) -> Content {
        var meters: [MenuBarMeter] = []

        if let shortID = descriptor.shortWindowID {
            if let window = report.windows.first(where: { $0.id == shortID }) {
                meters.append(windowMeter(letter: "S", window: window, now: now, role: .short))
            }
        } else if let spend = report.spend, let today = todayMeter(spend: spend, now: now, calendar: calendar) {
            meters.append(today)
        }

        if let meter = longMeter(descriptor: descriptor, report: report, now: now, calendar: calendar) {
            meters.append(meter)
        }

        return .meters(meters)
    }

    private static func longMeter(
        descriptor: ProviderDescriptor,
        report: ProviderReport,
        now: Date,
        calendar: Calendar
    ) -> MenuBarMeter? {
        let letter = descriptor.capabilities.hasCycle ? "C" : "W"
        let window = report.windows.first { $0.id == descriptor.longWindowID }
        let pacing = report.spend.flatMap { PacingCalculator.make($0, today: now, calendar: calendar) }

        guard let window else {
            guard let spend = report.spend, spend.limit == nil else {
                return nil
            }
            return MenuBarMeter(letter: letter, text: "∞", countdown: nil, fraction: nil, tick: nil, tint: .neutral, role: .long)
        }

        let countdown = window.resetsAt.map { CountdownFormatter.compact(until: $0, now: now) }

        // Team plans report dollars: the money row replaces the percent.
        if let money = report.extra(for: window.id) {
            guard let limit = money.limit else {
                return MenuBarMeter(
                    letter: letter, text: "\(spendText(money.amount))/—", countdown: countdown,
                    fraction: nil, tick: nil, tint: .neutral, role: .long
                )
            }

            return MenuBarMeter(
                letter: letter,
                text: "\(spendText(money.amount))/\(budgetText(limit))",
                countdown: countdown,
                fraction: pacing?.fillFraction ?? min(max(window.percentUsed / 100, 0), 1),
                tick: pacing?.tickFraction,
                tint: pacing.map { PacingTint.forPacing($0) } ?? PacingTint.forRemaining(percentUsed: window.percentUsed),
                role: .long
            )
        }

        guard let pacing else {
            return windowMeter(letter: letter, window: window, now: now, role: .long)
        }

        return MenuBarMeter(
            letter: letter,
            text: window.percentText,
            countdown: countdown,
            fraction: pacing.fillFraction,
            tick: pacing.tickFraction,
            tint: PacingTint.forPacing(pacing),
            role: .long
        )
    }

    private static func windowMeter(
        letter: String,
        window: LimitWindow,
        now: Date,
        role: MenuBarMeter.Role
    ) -> MenuBarMeter {
        MenuBarMeter(
            letter: letter,
            text: window.percentText,
            countdown: window.resetsAt.map { CountdownFormatter.compact(until: $0, now: now) },
            fraction: min(max(window.percentUsed / 100, 0), 1),
            tick: TimePacing.idealFraction(for: window, now: now),
            tint: PacingTint.forWindow(window, now: now),
            role: role
        )
    }

    /// nil when the spend has no budget to measure a day against.
    private static func todayMeter(spend: SpendPeriod, now: Date, calendar: Calendar) -> MenuBarMeter? {
        guard spend.limit != nil else {
            return nil
        }

        let unknown = MenuBarMeter(letter: "D", text: "—", countdown: nil, fraction: nil, tick: nil, tint: .neutral, role: .short)

        guard !spend.daily.isEmpty,
              let pacing = PacingCalculator.make(spend, today: now, calendar: calendar)
        else {
            return unknown
        }

        let spent = spend.spent(on: now, calendar: calendar)
        let budget = pacing.todayBudget
        let fraction = budget > 0
            ? min(max(NSDecimalNumber(decimal: spent / budget).doubleValue, 0), 1)
            : (spent > 0 ? 1 : 0)
        let text = spend.unit == .percent
            ? "\(String(percentText(spent).dropLast()))/\(percentText(budget))"
            : "\(spendText(spent))/\(budgetText(budget))"

        return MenuBarMeter(
            letter: "D",
            text: text,
            countdown: nil,
            fraction: fraction,
            tick: nil,
            tint: PacingTint.forSpend(spent, budget: budget),
            role: .short
        )
    }

    private static func apiMeter(
        spend: SpendPeriod,
        text: String,
        budget: Decimal?,
        now: Date,
        calendar: Calendar
    ) -> MenuBarMeter? {
        guard let budget, let pacing = PacingCalculator.make(spend, budgetOverride: budget, today: now, calendar: calendar) else {
            return nil
        }

        return MenuBarMeter(
            letter: "$",
            text: text,
            countdown: nil,
            fraction: pacing.fillFraction,
            tick: pacing.tickFraction,
            tint: PacingTint.forPacing(pacing),
            role: .spend
        )
    }

    private static let posix = Locale(identifier: "en_US_POSIX")

    static func spendText(_ amount: Decimal) -> String {
        amount.formatted(
            .number
                .precision(.fractionLength(2))
                .rounded(rule: .toNearestOrAwayFromZero)
                .grouping(.never)
                .locale(posix)
        )
    }

    /// Whole percent, with one decimal only below 10 where it still matters.
    static func percentText(_ percent: Decimal) -> String {
        let decimals = percent < 10 ? 0...1 : 0...0
        let text = percent.formatted(
            .number
                .precision(.fractionLength(decimals))
                .rounded(rule: .toNearestOrAwayFromZero)
                .grouping(.never)
                .locale(posix)
        )

        return "\(text)%"
    }

    static func budgetText(_ amount: Decimal) -> String {
        amount.formatted(
            .number
                .precision(.fractionLength(0))
                .rounded(rule: .toNearestOrAwayFromZero)
                .grouping(.never)
                .locale(posix)
        )
    }
}

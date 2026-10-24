import Foundation
import Testing
@testable import UsageTracker

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
    return calendar
}()

private func day(_ month: Int, _ day: Int, hour: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
}

private let now = day(10, 24, hour: 10)

private func cursorReport(
    unit: BudgetUnit,
    spent: Decimal,
    limit: Decimal?,
    todaySpend: Decimal?,
    percentUsed: Double?,
    periodEnd: Date = day(11, 11)
) -> ProviderReport {
    let period = CyclePeriod(start: day(10, 12), end: periodEnd)
    let daily = todaySpend.map { [DaySpend(day: day(10, 24), amount: $0)] } ?? []
    return ProviderReport(
        planName: nil,
        windows: percentUsed.map { [LimitWindow(id: "cycle", label: "Included usage", percentUsed: $0, resetsAt: periodEnd, parentID: nil)] } ?? [],
        // Dollar plans carry the cycle's amounts as a money row, as the mapper does.
        extras: unit == .dollars ? [MoneyRow(id: "cycle", label: "Included usage", amount: spent, limit: limit)] : [],
        spend: SpendPeriod(period: period, spent: spent, limit: limit, unit: unit, daily: daily)
    )
}

private func ready(_ report: ProviderReport?, stale: Bool = false) -> HalfSnapshot {
    HalfSnapshot(status: .ready, report: report, isStale: stale)
}

private func build(
    _ provider: Provider,
    subscription: HalfSnapshot?,
    api: HalfSnapshot? = nil,
    apiBudget: Decimal? = nil
) -> MenuBarItem? {
    MenuBarItemBuilder.make(
        descriptor: ProviderRegistry.descriptor(for: provider),
        subscription: subscription,
        api: api,
        apiBudget: apiBudget,
        now: now,
        calendar: calendar
    )
}

private func meters(_ display: HalfDisplay?) -> [MenuBarMeter] {
    if case let .meters(meters, _, _) = display { return meters }
    return []
}

private let anthropicReport = ProviderReport(
    planName: "Max",
    windows: [
        LimitWindow(id: "session", label: "Session", percentUsed: 41, resetsAt: now + 2 * 3600 + 10 * 60, parentID: nil),
        LimitWindow(id: "weekly", label: "Weekly", percentUsed: 70, resetsAt: now + 3 * 86400, parentID: nil),
    ],
    extras: [],
    spend: nil
)

private func apiReport(spent: Decimal) -> ProviderReport {
    ProviderReport(
        planName: nil, windows: [], extras: [],
        spend: SpendPeriod(
            period: CyclePeriod(start: day(10, 1), end: day(11, 1)),
            spent: spent, limit: nil, unit: .dollars, daily: []
        )
    )
}

@Suite struct MenuBarItemTests {
    @Test func cursorPercentPlanHasTodayAndCycleMeters() throws {
        let report = cursorReport(unit: .percent, spent: Decimal(string: "42.8")!, limit: 100, todaySpend: Decimal(string: "0.4")!, percentUsed: 43)
        let item = try #require(build(.cursor, subscription: ready(report)))
        let list = meters(item.subscription)

        #expect(list.count == 2)
        #expect(list[0].letter == "D")
        #expect(list[0].text == "0.4/3.2%")
        #expect(list[0].fraction == 0.125)
        #expect(list[0].tick == nil)
        #expect(list[1].letter == "C")
        #expect(list[1].text == "43%")
        let tick = try #require(list[1].tick)
        #expect(abs(tick - 13.0 / 30.0) < 0.0001)
        #expect(list[1].countdown == "17d")
        #expect(item.subscription == .meters(list, stale: false, errorMark: false))
        #expect(item.api == nil)
        #expect(!item.showsDivider)
    }

    @Test(arguments: [1e300, -1e300, Double.infinity, Double.nan])
    func extremePercentsRenderWithoutTrapping(percent: Double) throws {
        let window = LimitWindow(id: "session", label: "Session", percentUsed: percent, resetsAt: nil, parentID: nil)
        let report = ProviderReport(planName: nil, windows: [window], extras: [], spend: nil)
        let list = meters(build(.anthropic, subscription: ready(report))?.subscription)

        #expect(list.count == 1)
        #expect(list[0].text.hasSuffix("%"))
    }

    @Test func menuBarMoneyRoundsHalfUp() {
        #expect(MenuBarItemBuilder.spendText(Decimal(string: "2.985")!) == "2.99")
        #expect(MenuBarItemBuilder.spendText(Decimal(string: "15.345")!) == "15.35")
        #expect(MenuBarItemBuilder.spendText(Decimal(string: "0.005")!) == "0.01")
        #expect(MenuBarItemBuilder.budgetText(Decimal(string: "2.5")!) == "3")
        #expect(MenuBarItemBuilder.budgetText(Decimal(string: "3.5")!) == "4")
        #expect(MenuBarItemBuilder.percentText(Decimal(string: "12.5")!) == "13%")
        #expect(MenuBarItemBuilder.percentText(Decimal(string: "0.25")!) == "0.3%")
    }

    @Test func cursorTeamPlanShowsDollarsAndTick() throws {
        let report = cursorReport(unit: .dollars, spent: Decimal(string: "73.5")!, limit: 200, todaySpend: Decimal(string: "4.2")!, percentUsed: 36.75)
        let list = meters(build(.cursor, subscription: ready(report))?.subscription)

        #expect(list[0].text == "4.20/7")
        #expect(list[1].text == "73.50/200")
        let tick = try #require(list[1].tick)
        #expect(abs(tick - 13.0 / 30.0) < 0.0001)
        #expect(list[1].tint == .onPace)
    }

    @Test func teamPlanTextComesFromMoneyRow() throws {
        // A cached report from a cycle that has ended has no pacing; the text still comes from the money row.
        let report = cursorReport(unit: .dollars, spent: Decimal(string: "73.5")!, limit: 200, todaySpend: nil, percentUsed: 36.75, periodEnd: day(10, 20))
        let list = meters(build(.cursor, subscription: ready(report))?.subscription)
        let cycle = try #require(list.last)

        #expect(cycle.letter == "C")
        #expect(cycle.text == "73.50/200")
        #expect(cycle.fraction == 0.3675)
        #expect(cycle.tick == nil)
    }

    @Test func usedWithoutLimitShowsSpendOverDash() throws {
        let report = cursorReport(unit: .dollars, spent: Decimal(string: "73.5")!, limit: nil, todaySpend: Decimal(string: "4.2")!, percentUsed: 0)
        let list = meters(build(.cursor, subscription: ready(report))?.subscription)

        #expect(list.map(\.letter) == ["C"])
        #expect(list[0].text == "73.50/—")
        #expect(list[0].fraction == nil)
        #expect(list[0].tick == nil)
        #expect(list[0].tint == .neutral)
    }

    @Test func cursorUnlimitedShowsInfinity() throws {
        let report = cursorReport(unit: .dollars, spent: 12, limit: nil, todaySpend: nil, percentUsed: nil)
        let list = meters(build(.cursor, subscription: ready(report))?.subscription)

        #expect(list.map(\.text) == ["∞"])
        #expect(list[0].fraction == nil)
    }

    @Test func cursorTodayIsDashUntilDailyLoads() throws {
        let report = cursorReport(unit: .percent, spent: 40, limit: 100, todaySpend: nil, percentUsed: 40)
        let first = meters(build(.cursor, subscription: ready(report))?.subscription).first!

        #expect(first.letter == "D")
        #expect(first.text == "—")
        #expect(first.fraction == nil)
        #expect(first.tint == .neutral)
    }

    @Test func cursorTodayOverBudgetIsRed() throws {
        // 3 days left, 64 spent before today: today's budget is 12.
        let report = cursorReport(unit: .dollars, spent: 79, limit: 100, todaySpend: 15, percentUsed: 79, periodEnd: day(10, 27))
        let first = meters(build(.cursor, subscription: ready(report))?.subscription).first!

        #expect(first.text == "15.00/12")
        #expect(first.fraction == 1)
        #expect(first.tint == .overBudget)
    }

    @Test func anthropicHasSessionThenWeekly() throws {
        let item = try #require(build(.anthropic, subscription: ready(anthropicReport)))
        let list = meters(item.subscription)

        #expect(list.map(\.letter) == ["S", "W"])
        #expect(list.map(\.text) == ["41%", "70%"])
        #expect(list[0].countdown == "2h10")
        #expect(list[0].fraction == 0.41)
        #expect(list[0].tick == nil)
        #expect(list[0].tint == .onPace)
        #expect(list[1].tint == .nearingLimit)
    }

    private func timedReport(session: LimitWindow, weekly: LimitWindow) -> ProviderReport {
        ProviderReport(planName: "Max", windows: [session, weekly], extras: [], spend: nil)
    }

    @Test func sessionMeterCarriesTheTimeTick() throws {
        // 2h left of 5h: 3h elapsed, so the ideal is 60%.
        let session = LimitWindow(
            id: "session", label: "Session", percentUsed: 65, resetsAt: now + 2 * 3600, parentID: nil, windowLength: 5 * 3600
        )
        let weekly = LimitWindow(id: "weekly", label: "Weekly", percentUsed: 10, resetsAt: nil, parentID: nil)
        let list = meters(build(.anthropic, subscription: ready(timedReport(session: session, weekly: weekly)))?.subscription)

        let tick = try #require(list[0].tick)
        #expect(abs(tick - 0.6) < 0.0001)
        #expect(list[0].fraction == 0.65)
        // 65 / 60 is within 1.15 of the ideal.
        #expect(list[0].tint == .nearingLimit)
    }

    @Test func weeklyMeterCarriesTheTimeTick() throws {
        // 3d left of 7d: 4d elapsed, so the ideal is 4/7.
        let session = LimitWindow(id: "session", label: "Session", percentUsed: 10, resetsAt: nil, parentID: nil)
        let weekly = LimitWindow(
            id: "weekly", label: "Weekly", percentUsed: 60, resetsAt: now + 3 * 86400, parentID: nil, windowLength: 7 * 86400
        )
        let list = meters(build(.anthropic, subscription: ready(timedReport(session: session, weekly: weekly)))?.subscription)

        let tick = try #require(list[1].tick)
        #expect(abs(tick - 4.0 / 7.0) < 0.0001)
        // 60 / 57.1 is about 1.05.
        #expect(list[1].tint == .nearingLimit)
    }

    @Test func closedWindowsHaveNoTickOrCountdown() throws {
        let closed = LimitWindow(id: "session", label: "Session", percentUsed: 0, resetsAt: nil, parentID: nil, windowLength: 5 * 3600)
        let weekly = LimitWindow(id: "weekly", label: "Weekly", percentUsed: 10, resetsAt: nil, parentID: nil)
        let list = meters(build(.anthropic, subscription: ready(timedReport(session: closed, weekly: weekly)))?.subscription)

        #expect(list[0].tick == nil)
        #expect(list[0].countdown == nil)
        #expect(list[0].text == "0%")
        #expect(list[0].tint == PacingTint.forRemaining(percentUsed: 0))
        #expect(PopoverPresentation.rowPacing(window: closed, now: now).tick == nil)
    }

    @Test func unconfiguredHalvesMakeNoItem() {
        let none = HalfSnapshot(status: .unconfigured, report: nil, isStale: true)
        #expect(build(.anthropic, subscription: none, api: none) == nil)
        #expect(build(.anthropic, subscription: nil, api: nil) == nil)
    }

    @Test func unconfiguredHalfIsAbsentButOtherRemains() throws {
        let none = HalfSnapshot(status: .unconfigured, report: nil, isStale: true)
        let item = try #require(build(.anthropic, subscription: ready(anthropicReport), api: none))
        #expect(item.api == nil)
        #expect(!item.showsDivider)
    }

    @Test func loadingWithoutReportIsStatus() throws {
        let loading = HalfSnapshot(status: .loading, report: nil, isStale: true)
        #expect(try #require(build(.anthropic, subscription: loading)).subscription == .status(.loading))
    }

    @Test func expiredReplacesMeters() throws {
        let expired = HalfSnapshot(status: .expired, report: anthropicReport, isStale: true)
        #expect(try #require(build(.anthropic, subscription: expired)).subscription == .status(.expired))
    }

    @Test(arguments: [false, true])
    func waitingForAnOrganizationShowsTheSetUpStatus(hasCachedReport: Bool) throws {
        let waiting = HalfSnapshot(status: .needsOrganization, report: hasCachedReport ? anthropicReport : nil, isStale: true)
        #expect(try #require(build(.anthropic, subscription: waiting)).subscription == .status(.setUp))
    }

    @Test func errorWithoutReportIsStatus() throws {
        let failed = HalfSnapshot(status: .error, report: nil, isStale: true)
        #expect(try #require(build(.anthropic, subscription: failed)).subscription == .status(.error))
    }

    @Test func errorWithCachedReportKeepsMetersDimmedWithMark() throws {
        let failed = HalfSnapshot(status: .error, report: anthropicReport, isStale: false)
        guard case let .meters(list, stale, errorMark) = try #require(build(.anthropic, subscription: failed)).subscription else {
            Issue.record("expected meters")
            return
        }
        #expect(list.count == 2)
        #expect(stale)
        #expect(errorMark)
    }

    @Test func errorWithCachedAPIReportIsDimmedWithMark() throws {
        let failed = HalfSnapshot(status: .error, report: apiReport(spent: Decimal(string: "37.84")!), isStale: false)
        let item = try #require(build(.anthropic, subscription: nil, api: failed))
        #expect(item.api == .money(text: "$37.84", meter: nil, stale: true, errorMark: true))
    }

    @Test func staleCachedReportIsFlagged() throws {
        let item = try #require(build(.anthropic, subscription: ready(anthropicReport, stale: true)))
        guard case let .meters(_, stale, errorMark) = item.subscription else {
            Issue.record("expected meters")
            return
        }
        #expect(stale)
        #expect(!errorMark)
    }

    @Test func apiMoneyWithoutBudgetHasNoMeter() throws {
        let item = try #require(build(.anthropic, subscription: ready(anthropicReport), api: ready(apiReport(spent: Decimal(string: "37.84")!))))
        #expect(item.api == .money(text: "$37.84", meter: nil, stale: false, errorMark: false))
        #expect(item.showsDivider)
    }

    @Test func apiMoneyWithBudgetHasTickAndFraction() throws {
        let item = try #require(build(.anthropic, subscription: nil, api: ready(apiReport(spent: Decimal(string: "37.84")!)), apiBudget: 100))
        guard case let .money(text, meter, _, _) = item.api else {
            Issue.record("expected money")
            return
        }
        let apiMeter = try #require(meter)
        #expect(text == "$37.84")
        #expect(apiMeter.letter == "$")
        #expect(abs(try #require(apiMeter.fraction) - 0.3784) < 0.0001)
        let tick = try #require(apiMeter.tick)
        #expect(abs(tick - 24.0 / 31.0) < 0.0001)
        #expect(item.subscription == nil)
    }

    @Test func apiReportWithoutSpendIsError() throws {
        let item = try #require(build(.anthropic, subscription: nil, api: ready(ProviderReport(planName: nil, windows: [], extras: [], spend: nil))))
        #expect(item.api == .status(.error))
    }

    @Test func accessibilityText() throws {
        let item = try #require(build(.anthropic, subscription: ready(anthropicReport), api: ready(apiReport(spent: Decimal(string: "37.84")!))))
        #expect(item.accessibilityText(displayName: "Anthropic") == "Anthropic, S 41%, W 70%, API $37.84")

        let expired = HalfSnapshot(status: .expired, report: nil, isStale: true)
        let expiredItem = try #require(build(.anthropic, subscription: expired))
        #expect(expiredItem.accessibilityText(displayName: "Anthropic") == "Anthropic, Plan usage: credential expired")

        let cursor = cursorReport(unit: .percent, spent: 53, limit: 100, todaySpend: nil, percentUsed: 53)
        let cursorItem = try #require(build(.cursor, subscription: ready(cursor)))
        #expect(cursorItem.accessibilityText(displayName: "Cursor") == "Cursor, C 53%")

        let withData = cursorReport(unit: .dollars, spent: Decimal(string: "73.5")!, limit: 200, todaySpend: Decimal(string: "4.2")!, percentUsed: 53)
        let dataItem = try #require(build(.cursor, subscription: ready(withData)))
        #expect(dataItem.accessibilityText(displayName: "Cursor") == "Cursor, D 4.20/7, C 73.50/200")
    }

    @Test func accessibilityTextNamesTheFailingHalf() throws {
        let failedWithReport = HalfSnapshot(status: .error, report: anthropicReport, isStale: false)
        let failedWithout = HalfSnapshot(status: .error, report: nil, isStale: true)

        let subscriptionFailed = try #require(build(.anthropic, subscription: failedWithReport, api: ready(apiReport(spent: 1))))
        #expect(subscriptionFailed.accessibilityText(displayName: "Anthropic") == "Anthropic, S 41%, W 70%, Plan usage: refresh failed, API $1.00")

        let apiFailed = try #require(build(.anthropic, subscription: ready(anthropicReport), api: failedWithout))
        #expect(apiFailed.accessibilityText(displayName: "Anthropic") == "Anthropic, S 41%, W 70%, API spend: refresh failed")

        let apiFailedWithReport = HalfSnapshot(status: .error, report: apiReport(spent: 1), isStale: false)
        let moneyFailed = try #require(build(.anthropic, subscription: nil, api: apiFailedWithReport))
        #expect(moneyFailed.accessibilityText(displayName: "Anthropic") == "Anthropic, API $1.00, API spend: refresh failed")
    }
}

@Test func forceSetUpShowsOnlyTheSetUpStatus() {
    let item = MenuBarItemBuilder.make(
        descriptor: ProviderRegistry.descriptor(for: .cursor),
        subscription: HalfSnapshot(status: .unconfigured, report: nil, isStale: true),
        api: nil,
        apiBudget: nil,
        now: now,
        calendar: calendar,
        forceSetUp: true
    )
    #expect(item == MenuBarItem(provider: .cursor, subscription: .status(.setUp), api: nil))
}

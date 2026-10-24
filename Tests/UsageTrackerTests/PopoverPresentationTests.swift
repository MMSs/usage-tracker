import Foundation
import Testing
@testable import UsageTracker

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
    return calendar
}()

private func date(_ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}

private func pacing(status: PacingStatus, remainingDays: Int = 18) -> Pacing {
    Pacing(
        totalDays: 30, elapsedDays: 30 - remainingDays, remainingDays: remainingDays,
        spent: 120, idealSpend: 120, status: status, todayBudget: 10, leftForToday: 5,
        projectedSpend: nil, tickFraction: 0.4, fillFraction: 0.3
    )
}

private let cycleWindow = LimitWindow(id: "cycle", label: "Included usage", percentUsed: 53, resetsAt: nil, parentID: nil)

private func cycleMoney(limit: Decimal?) -> MoneyRow {
    MoneyRow(id: "cycle", label: "Included usage", amount: Decimal(string: "73.5")!, limit: limit)
}

@Suite struct PopoverPresentationTests {
    @Test func pillTextDollars() {
        #expect(PopoverPresentation.pillText(pacing(status: .onTrack(by: Decimal(string: "12.4")!)), unit: .dollars) == "On track by $12.40")
        #expect(PopoverPresentation.pillText(pacing(status: .over(by: Decimal(string: "3.1")!)), unit: .dollars) == "Over by $3.10")
    }

    @Test func pillTextPercent() {
        #expect(PopoverPresentation.pillText(pacing(status: .onTrack(by: Decimal(string: "4.2")!)), unit: .percent) == "On track by 4.2%")
    }

    @Test func pillSymbolFollowsTint() {
        #expect(PopoverPresentation.pillSymbol(.onPace) == "checkmark.circle.fill")
        #expect(PopoverPresentation.pillSymbol(.nearingLimit) == "exclamationmark.circle.fill")
        #expect(PopoverPresentation.pillSymbol(.overBudget) == "exclamationmark.triangle.fill")
    }

    @Test func daysLeft() {
        #expect(PopoverPresentation.daysLeftText(pacing(status: .onTrack(by: 0), remainingDays: 18)) == "18 days left")
        #expect(PopoverPresentation.daysLeftText(pacing(status: .onTrack(by: 0), remainingDays: 1)) == "1 day left")
    }

    @Test func rowTextShowsPercent() {
        #expect(PopoverPresentation.rowText(window: cycleWindow, money: nil, resetText: nil, daysLeft: nil) == "53%")
    }

    @Test(arguments: [1e300, -1e300, Double.infinity, -Double.infinity, Double.nan])
    func rowTextSurvivesAnyPercent(percent: Double) {
        let window = LimitWindow(id: "w", label: "W", percentUsed: percent, resetsAt: nil, parentID: nil)

        #expect(PopoverPresentation.rowText(window: window, money: nil, resetText: nil, daysLeft: nil).hasSuffix("%"))
    }

    @Test func rowTextClampsHugePercents() {
        let window = LimitWindow(id: "w", label: "W", percentUsed: 1e300, resetsAt: nil, parentID: nil)

        #expect(PopoverPresentation.rowText(window: window, money: nil, resetText: nil, daysLeft: nil) == "999999%")
    }

    @Test func rowTextAppendsResetText() {
        #expect(PopoverPresentation.rowText(window: cycleWindow, money: nil, resetText: "resets in 2h 10m", daysLeft: nil) == "53% · resets in 2h 10m")
    }

    @Test func cycleRowTextShowsDaysLeftInPlaceOfResetText() {
        #expect(PopoverPresentation.rowText(window: cycleWindow, money: nil, resetText: "resets 11 Nov", daysLeft: "18 days left") == "53% · 18 days left")
    }

    @Test func rowTextShowsTeamSpendAgainstLimitInPlaceOfPercent() {
        #expect(PopoverPresentation.rowText(window: cycleWindow, money: cycleMoney(limit: 200), resetText: nil, daysLeft: nil) == "$73.50 / $200.00")
        #expect(PopoverPresentation.rowText(window: cycleWindow, money: cycleMoney(limit: 200), resetText: "resets 11 Nov", daysLeft: "18 days left") == "$73.50 / $200.00 · 18 days left")
    }

    @Test func rowTextShowsTeamSpendWithoutLimit() {
        #expect(PopoverPresentation.rowText(window: cycleWindow, money: cycleMoney(limit: nil), resetText: "resets 11 Nov", daysLeft: nil) == "$73.50 · resets 11 Nov")
    }

    @Test func rowHasNoBarForSpendWithoutALimit() {
        #expect(PopoverPresentation.rowFraction(window: cycleWindow, money: nil) == 0.53)
        #expect(PopoverPresentation.rowFraction(window: cycleWindow, money: cycleMoney(limit: 200)) == 0.53)
        #expect(PopoverPresentation.rowFraction(window: cycleWindow, money: cycleMoney(limit: nil)) == nil)
    }

    @Test func updatedTextUses24HourClock() {
        #expect(PopoverPresentation.updatedText(date(10, 24, hour: 14, minute: 31), calendar: calendar) == "Updated 14:31")
        #expect(PopoverPresentation.updatedText(date(10, 24, hour: 9, minute: 5), calendar: calendar) == "Updated 09:05")
        #expect(PopoverPresentation.updatedText(nil, calendar: calendar) == "Updated —")
    }

    private static let claude = HalfService(name: "claude.ai", host: "claude.ai")
    private static let console = HalfService(name: "Anthropic API", host: "api.anthropic.com")

    private func error(_ failure: RefreshFailure?, half: Half = .subscription, service: HalfService = claude) -> HalfErrorMessage? {
        PopoverPresentation.halfError(half: half, status: .error, failure: failure, service: service)
    }

    @Test func transportNamesTheHost() {
        #expect(error(.transport, half: .api, service: Self.console) == HalfErrorMessage(
            text: "API spend: Couldn't reach api.anthropic.com.",
            fix: "Check your connection; it retries automatically.",
            severity: .warning
        ))
    }

    @Test func challengeSendsTheUserToTheBrowser() {
        #expect(error(.challenge) == HalfErrorMessage(
            text: "Plan usage: claude.ai asked for a browser check.",
            fix: "Open claude.ai in your browser, then Refresh.",
            severity: .warning
        ))
    }

    @Test func httpStatusNamesTheServiceAndCode() {
        #expect(error(.httpStatus(429), half: .api, service: Self.console) == HalfErrorMessage(
            text: "API spend: Anthropic API returned an error (HTTP 429).",
            fix: "It retries automatically.",
            severity: .warning
        ))
    }

    private func rateLimited(until: Date, now: Date) -> HalfErrorMessage? {
        PopoverPresentation.halfError(
            half: .api, status: .error, failure: .rateLimited(until: until),
            service: Self.console, now: now, calendar: calendar
        )
    }

    @Test func rateLimitedSaysWhenItRetries() {
        #expect(rateLimited(until: date(10, 24, hour: 21, minute: 5), now: date(10, 24, hour: 20, minute: 55)) == HalfErrorMessage(
            text: "API spend: Anthropic API is rate limiting requests; retrying at 21:05.",
            fix: nil,
            severity: .warning
        ))
    }

    @Test func rateLimitedPastMidnightNamesTheDay() {
        #expect(rateLimited(until: date(10, 25, hour: 0, minute: 30), now: date(10, 24, hour: 23, minute: 50))?.text
            == "API spend: Anthropic API is rate limiting requests; retrying at 25 Oct, 00:30.")
    }

    /// A wait already over gives no time: "retrying at <past time>" would be wrong.
    @Test(arguments: [0.0, -60, -3600])
    func rateLimitedWithAPastTimeGivesNoTime(offset: TimeInterval) {
        let now = date(10, 24, hour: 20, minute: 55)
        #expect(rateLimited(until: now.addingTimeInterval(offset), now: now) == HalfErrorMessage(
            text: "API spend: Anthropic API is rate limiting requests.",
            fix: "It retries automatically.",
            severity: .warning
        ))
    }

    @Test func rateLimitedWithoutATimeStillRetries() {
        #expect(error(.rateLimited(until: nil), half: .api, service: Self.console) == HalfErrorMessage(
            text: "API spend: Anthropic API is rate limiting requests.",
            fix: "It retries automatically.",
            severity: .warning
        ))
    }

    @Test func decodingSuggestsAnUpdate() {
        #expect(error(.decoding) == HalfErrorMessage(
            text: "Plan usage: claude.ai sent a response the app doesn't understand.",
            fix: "It may have changed; check for an update.",
            severity: .warning
        ))
    }

    @Test func keychainFailure() {
        #expect(error(.keychain)?.text == "Plan usage: Couldn't read the credential from Keychain.")
        #expect(error(.keychain)?.fix == "Unlock the login keychain and allow access if asked, then Refresh.")
    }

    @Test func unexpectedFailure() {
        #expect(error(.unexpected)?.text == "Plan usage: Refreshing from claude.ai failed unexpectedly.")
        #expect(error(.unexpected)?.fix == "It retries automatically.")
    }

    @Test func errorWithoutACauseStillExplainsItself() {
        #expect(error(nil) == HalfErrorMessage(text: "Plan usage: Unable to refresh.", fix: "It retries automatically.", severity: .warning))
    }

    @Test func expiredKeepsTheExistingText() {
        let message = PopoverPresentation.halfError(half: .api, status: .expired, failure: .unauthorized, service: Self.console)
        #expect(message == HalfErrorMessage(text: "API spend: Credential expired — replace it in Settings", fix: nil, severity: .critical))
    }

    @Test(arguments: [HalfStatus.ready, .loading, .unconfigured])
    func healthyStatesHaveNoError(status: HalfStatus) {
        #expect(PopoverPresentation.halfError(half: .subscription, status: status, failure: .transport, service: Self.claude) == nil)
    }

    /// The menu bar shows "Error" for a report with nothing it can draw; the popover must say why.
    @Test(arguments: [HalfStatus.ready, .loading])
    func reportTheMenuBarCannotDrawIsExplained(status: HalfStatus) {
        let message = PopoverPresentation.halfError(
            half: .api, status: status, failure: nil, service: Self.console, display: .status(.error)
        )
        #expect(message == HalfErrorMessage(
            text: "API spend: Anthropic API sent nothing the app can show.",
            fix: "It may have changed; check for an update.",
            severity: .warning
        ))

        let drawable = HalfDisplay.money(text: "$1.00", meter: nil, stale: false, errorMark: false)
        #expect(PopoverPresentation.halfError(half: .api, status: status, failure: nil, service: Self.console, display: drawable) == nil)
        #expect(PopoverPresentation.halfError(half: .api, status: status, failure: nil, service: Self.console, display: .status(.loading)) == nil)
    }

    @Test func lineJoinsTextAndFix() {
        #expect(error(.httpStatus(500))?.line == "Plan usage: claude.ai returned an error (HTTP 500). It retries automatically.")
        #expect(HalfErrorMessage(text: "A", fix: nil, severity: .critical).line == "A")
    }

    @Test func lastSuccessShowsTheTimeTodayAndTheDayOtherwise() {
        let now = date(10, 24, hour: 16)
        #expect(PopoverPresentation.lastSuccessText(date(10, 24, hour: 14, minute: 31), now: now, calendar: calendar) == "Last success 14:31")
        #expect(PopoverPresentation.lastSuccessText(date(10, 22, hour: 9, minute: 5), now: now, calendar: calendar) == "Last success 22 Oct, 09:05")
        #expect(PopoverPresentation.lastSuccessText(nil, now: now, calendar: calendar) == nil)
    }

    @Test func monthNameIsEnglishWide() {
        #expect(PopoverPresentation.monthName(for: date(10, 12), calendar: calendar) == "October")
    }

    @Test func effectiveBudgetIgnoresNonPositive() {
        #expect(PopoverPresentation.effectiveBudget(nil) == nil)
        #expect(PopoverPresentation.effectiveBudget(0) == nil)
        #expect(PopoverPresentation.effectiveBudget(-5) == nil)
        #expect(PopoverPresentation.effectiveBudget(100) == 100)
    }

    @Test func headerSubtitle() {
        let cycle = CyclePeriod(start: date(10, 12), end: date(11, 11))
        #expect(PopoverPresentation.headerSubtitle(cycle: cycle, planName: "Pro", calendar: calendar) == "12 Oct → 10 Nov")
        #expect(PopoverPresentation.headerSubtitle(cycle: nil, planName: "Pro", calendar: calendar) == "Pro")
        #expect(PopoverPresentation.headerSubtitle(cycle: nil, planName: nil, calendar: calendar) == nil)
    }

    @Test func projectedTileSplitsAmountFromTheLastDay() {
        let projected = Pacing(
            totalDays: 30, elapsedDays: 12, remainingDays: 18,
            spent: 120, idealSpend: 120, status: .onTrack(by: 0), todayBudget: 10, leftForToday: 5,
            projectedSpend: Decimal(string: "0.01")!, tickFraction: 0.4, fillFraction: 0.3
        )

        #expect(PopoverPresentation.projectedValue(projected, unit: .dollars) == "$0.01")
        #expect(PopoverPresentation.projectedCaption(projected, periodEnd: date(11, 1), calendar: calendar) == "by 31 Oct")
    }

    @Test func projectedTileWithoutAProjectionIsADashWithNoCaption() {
        let none = pacing(status: .onTrack(by: 0))

        #expect(PopoverPresentation.projectedValue(none, unit: .dollars) == "—")
        #expect(PopoverPresentation.projectedCaption(none, periodEnd: date(11, 1), calendar: calendar) == nil)
    }

    @Test func rowPacingFallsBackToRemainingTint() {
        let window = LimitWindow(id: "weekly", label: "Weekly", percentUsed: 85, resetsAt: date(10, 27), parentID: nil)
        let result = PopoverPresentation.rowPacing(window: window, now: date(10, 24))

        #expect(result.tick == nil)
        #expect(result.tint == .overBudget)
    }

    @Test func rowPacingUsesElapsedTimeWhenTheWindowHasALength() throws {
        // 2h left of 5h: the ideal is 60%.
        let window = LimitWindow(
            id: "session", label: "Session", percentUsed: 30, resetsAt: date(10, 24, hour: 12), parentID: nil, windowLength: 5 * 3600
        )
        let result = PopoverPresentation.rowPacing(window: window, now: date(10, 24, hour: 10))

        let tick = try #require(result.tick)
        #expect(abs(tick - 0.6) < 0.0001)
        #expect(result.tint == .onPace)
    }
}

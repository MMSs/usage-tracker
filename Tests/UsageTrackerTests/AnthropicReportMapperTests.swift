import Foundation
import Testing
@testable import UsageTracker

struct AnthropicReportMapperTests {
    private typealias Window = AnthropicUsageResponse.UsageWindow
    private typealias Scoped = AnthropicUsageResponse.ScopedLimit

    private let fiveHourReset = Date(timeIntervalSince1970: 1_792_000_000)
    private let weeklyReset = Date(timeIntervalSince1970: 1_792_400_000)

    private func snapshot(
        fiveHour: Window? = nil,
        sevenDay: Window? = nil,
        limits: [Scoped] = [],
        legacy: [String: Window] = [:],
        planName: String? = nil,
        spendLimit: AnthropicOverageSpendLimit? = nil,
        creditGrant: AnthropicOverageCreditGrant? = nil
    ) -> AnthropicSubscriptionSnapshot {
        AnthropicSubscriptionSnapshot(
            usage: AnthropicUsageResponse(
                fiveHour: fiveHour,
                sevenDay: sevenDay,
                limits: limits,
                legacyModelWindows: legacy
            ),
            planName: planName,
            spendLimit: spendLimit,
            creditGrant: creditGrant
        )
    }

    private func scoped(id: String?, name: String?, percent: Double?, kind: String = "weekly_scoped") -> Scoped {
        Scoped(kind: kind, percent: percent, resetsAt: weeklyReset, modelID: id, modelDisplayName: name)
    }

    @Test func sessionAndWeeklyCarryTheirLengths() {
        let report = AnthropicReportMapper.subscription(snapshot(
            fiveHour: Window(utilization: 42, resetsAt: fiveHourReset),
            sevenDay: Window(utilization: 17.5, resetsAt: weeklyReset),
            planName: "Max 5x"
        ))

        #expect(report.planName == "Max 5x")
        #expect(report.spend == nil)
        #expect(report.windows == [
            LimitWindow(id: "session", label: "Session", percentUsed: 42, resetsAt: fiveHourReset, parentID: nil, windowLength: 5 * 3600),
            LimitWindow(id: "weekly", label: "Weekly", percentUsed: 17.5, resetsAt: weeklyReset, parentID: nil, windowLength: 7 * 86400),
        ])
    }

    @Test func nonFiniteOverageAmountsMapToZero() {
        let report = AnthropicReportMapper.subscription(snapshot(
            spendLimit: AnthropicOverageSpendLimit(
                isEnabled: true, usedCredits: .nan, monthlyCreditLimit: .infinity, currency: nil
            ),
            creditGrant: AnthropicOverageCreditGrant(granted: true, amountMinorUnits: -.infinity, currency: nil)
        ))

        #expect(report.extras.map(\.amount) == [0, 0])
        #expect(report.extras[0].limit == 0)
    }

    @Test func hugeOverageAmountsDoNotProduceNaN() {
        let report = AnthropicReportMapper.subscription(snapshot(
            creditGrant: AnthropicOverageCreditGrant(granted: true, amountMinorUnits: 1e300, currency: nil)
        ))

        #expect(report.extras[0].amount.isFinite)
    }

    @Test func scopedLimitsBecomeChildrenOfWeekly() {
        let report = AnthropicReportMapper.subscription(snapshot(
            sevenDay: Window(utilization: 30, resetsAt: weeklyReset),
            limits: [
                scoped(id: "model_b", name: "Model B", percent: 12),
                scoped(id: "model_a", name: nil, percent: 8),
                scoped(id: nil, name: "No id", percent: 5),
                scoped(id: nil, name: nil, percent: 4),
                scoped(id: "empty", name: "", percent: 3),
                scoped(id: "other", name: "Other", percent: 1, kind: "session"),
            ]
        ))

        #expect(report.windows.map(\.id) == ["weekly", "weekly:model_b", "weekly:model_a", "weekly:no-id", "weekly:empty"])
        #expect(report.windows.map(\.label) == ["Weekly", "Model B", "model_a", "No id", "empty"])
        #expect(report.children(of: "weekly").map(\.percentUsed) == [12, 8, 5, 3])
        #expect(report.children(of: "weekly").allSatisfy { $0.windowLength == 7 * 86400 && $0.resetsAt == weeklyReset })
    }

    @Test func scopedLimitWithOnlyADisplayNameGetsASlugID() {
        let report = AnthropicReportMapper.subscription(snapshot(
            sevenDay: Window(utilization: 30, resetsAt: weeklyReset),
            limits: [
                scoped(id: nil, name: "Fable", percent: 15),
                scoped(id: nil, name: "  Claude  Opus 5.5! ", percent: 7),
                scoped(id: nil, name: "!!!", percent: 2),
            ]
        ))

        #expect(report.windows.map(\.id) == ["weekly", "weekly:fable", "weekly:claude-opus-5-5", "weekly:scoped"])
        #expect(report.windows.map(\.label) == ["Weekly", "Fable", "  Claude  Opus 5.5! ", "!!!"])
        #expect(report.children(of: "weekly").allSatisfy { $0.parentID == "weekly" && $0.windowLength == 7 * 86400 })
    }

    @Test func liveFixtureYieldsSessionWeeklyAndFable() throws {
        let url = try #require(Bundle.module.url(forResource: "anthropic-usage", withExtension: "json", subdirectory: "Fixtures"))
        let usage = try AnthropicUsageResponse.decoder().decode(AnthropicUsageResponse.self, from: Data(contentsOf: url))

        let report = AnthropicReportMapper.subscription(AnthropicSubscriptionSnapshot(
            usage: usage, planName: nil, spendLimit: nil, creditGrant: nil
        ))

        #expect(report.windows.map(\.id) == ["session", "weekly", "weekly:fable"])
        #expect(report.windows.map(\.label) == ["Session", "Weekly", "Fable"])
        #expect(report.windows.map(\.percentUsed) == [30, 25, 15])
        #expect(report.windows[2].parentID == "weekly")
    }

    @Test func legacyKeysAreUsedOnlyWithoutScopedLimits() {
        let legacy = [
            "sonnet_beta": Window(utilization: 20, resetsAt: weeklyReset),
            "alpha": Window(utilization: 10, resetsAt: weeklyReset),
            "unused": Window(utilization: nil, resetsAt: nil),
        ]
        let sevenDay = Window(utilization: 30, resetsAt: weeklyReset)

        let fallback = AnthropicReportMapper.subscription(snapshot(sevenDay: sevenDay, legacy: legacy))
        #expect(fallback.windows.map(\.id) == ["weekly", "weekly:alpha", "weekly:sonnet_beta"])
        #expect(fallback.windows.map(\.label) == ["Weekly", "Alpha", "Sonnet beta"])
        #expect(fallback.children(of: "weekly").allSatisfy { $0.windowLength == 7 * 86400 })

        let scopedWins = AnthropicReportMapper.subscription(snapshot(
            sevenDay: sevenDay,
            limits: [scoped(id: "model_a", name: "Model A", percent: 8)],
            legacy: legacy
        ))
        #expect(scopedWins.windows.map(\.id) == ["weekly", "weekly:model_a"])
    }

    @Test func childrenWithoutAWeeklyParentAreDropped() {
        let report = AnthropicReportMapper.subscription(snapshot(
            fiveHour: Window(utilization: 5, resetsAt: fiveHourReset),
            limits: [scoped(id: "model_a", name: "Model A", percent: 8)],
            legacy: ["alpha": Window(utilization: 10, resetsAt: weeklyReset)]
        ))

        #expect(report.windows.map(\.id) == ["session"])
    }

    @Test func disabledSpendLimitIsNotShown() {
        let report = AnthropicReportMapper.subscription(snapshot(
            spendLimit: AnthropicOverageSpendLimit(isEnabled: false, usedCredits: 5, monthlyCreditLimit: 50, currency: "USD")
        ))

        #expect(report.extras.isEmpty)
    }

    @Test func extrasAppearWhenPresent() {
        let report = AnthropicReportMapper.subscription(snapshot(
            spendLimit: AnthropicOverageSpendLimit(isEnabled: true, usedCredits: 12.34, monthlyCreditLimit: 50, currency: "USD"),
            creditGrant: AnthropicOverageCreditGrant(granted: true, amountMinorUnits: 1250, currency: "USD")
        ))

        #expect(report.extras == [
            MoneyRow(id: "overage", label: "Extra usage", amount: Decimal(string: "12.34")!, limit: 50),
            MoneyRow(id: "credits", label: "Extra credits", amount: Decimal(string: "12.5")!, limit: nil),
        ])
    }

    @Test(arguments: [
        AnthropicOverageCreditGrant(granted: false, amountMinorUnits: nil, currency: nil),
        AnthropicOverageCreditGrant(granted: false, amountMinorUnits: 1250, currency: "USD"),
        AnthropicOverageCreditGrant(granted: true, amountMinorUnits: nil, currency: "USD"),
        AnthropicOverageCreditGrant(granted: nil, amountMinorUnits: 1250, currency: "USD"),
    ])
    func creditsAreShownOnlyWhenGrantedWithAnAmount(grant: AnthropicOverageCreditGrant) {
        let report = AnthropicReportMapper.subscription(snapshot(creditGrant: grant))

        #expect(report.extras.isEmpty)
    }

    @Test func fractionalAmountsStayExact() {
        let report = AnthropicReportMapper.subscription(snapshot(
            spendLimit: AnthropicOverageSpendLimit(isEnabled: true, usedCredits: 12.34, monthlyCreditLimit: 0.1, currency: nil)
        ))

        #expect(report.extras.first?.amount == Decimal(string: "12.34"))
        #expect(report.extras.first?.limit == Decimal(string: "0.1"))
    }

    @Test func missingUtilizationReadsZero() {
        let report = AnthropicReportMapper.subscription(snapshot(
            fiveHour: Window(utilization: nil, resetsAt: fiveHourReset),
            sevenDay: Window(utilization: nil, resetsAt: weeklyReset),
            limits: [scoped(id: "model_a", name: "Model A", percent: nil)]
        ))

        #expect(report.windows.map(\.percentUsed) == [0, 0, 0])
    }
}

struct AnthropicAPIReportMapperTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        return calendar
    }()

    private func local(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
    }

    @Test func spendIsTheSumOfTheDailySeries() {
        let month = CyclePeriod(start: local(10, 1), end: local(11, 1))
        let days = [
            AnthropicCostDay(day: local(10, 1), dollars: Decimal(string: "12.345678")!),
            AnthropicCostDay(day: local(10, 3), dollars: Decimal(string: "2.995")!),
        ]

        let report = AnthropicReportMapper.api(days: days, month: month, today: local(10, 24), calendar: calendar)

        #expect(report.planName == nil)
        #expect(report.windows.isEmpty)
        #expect(report.extras.isEmpty)
        #expect(report.spend == SpendPeriod(
            period: month,
            spent: Decimal(string: "15.340678")!,
            limit: nil,
            unit: .dollars,
            daily: [
                DaySpend(day: local(10, 1), amount: Decimal(string: "12.345678")!),
                DaySpend(day: local(10, 3), amount: Decimal(string: "2.995")!),
            ]
        ))
    }

    @Test func noDaysIsAZeroSpendMonth() {
        let month = CyclePeriod(start: local(10, 1), end: local(11, 1))

        let report = AnthropicReportMapper.api(days: [], month: month, today: local(10, 24), calendar: calendar)

        #expect(report.spend == SpendPeriod(period: month, spent: 0, limit: nil, unit: .dollars, daily: []))
    }

    @Test func bucketsAfterLocalTodayFoldIntoToday() {
        let month = CyclePeriod(start: local(10, 1), end: local(11, 1))
        // 24 Oct 20:00 in Los Angeles is already 25 Oct in UTC, so the Admin
        // API can have a bucket for a local day that has not started.
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 20))!
        let days = [
            AnthropicCostDay(day: local(10, 23), dollars: 1),
            AnthropicCostDay(day: local(10, 24), dollars: 2),
            AnthropicCostDay(day: local(10, 25), dollars: Decimal(string: "0.5")!),
        ]

        let report = AnthropicReportMapper.api(days: days, month: month, today: today, calendar: calendar)

        #expect(report.spend?.daily == [
            DaySpend(day: local(10, 23), amount: 1),
            DaySpend(day: local(10, 24), amount: Decimal(string: "2.5")!),
        ])
        #expect(report.spend?.spent == Decimal(string: "3.5"))
    }

    @Test func futureBucketCreatesTodayWhenTodayHasNoEntry() {
        let month = CyclePeriod(start: local(10, 1), end: local(11, 1))
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 20))!
        let days = [
            AnthropicCostDay(day: local(10, 22), dollars: 1),
            AnthropicCostDay(day: local(10, 25), dollars: 4),
            AnthropicCostDay(day: local(10, 26), dollars: 1),
        ]

        let report = AnthropicReportMapper.api(days: days, month: month, today: today, calendar: calendar)

        #expect(report.spend?.daily == [
            DaySpend(day: local(10, 22), amount: 1),
            DaySpend(day: local(10, 24), amount: 5),
        ])
        #expect(report.spend?.spent == 6)
    }
}

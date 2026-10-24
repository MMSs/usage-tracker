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

    @Test func scopedLimitsBecomeChildrenOfWeekly() {
        let report = AnthropicReportMapper.subscription(snapshot(
            sevenDay: Window(utilization: 30, resetsAt: weeklyReset),
            limits: [
                scoped(id: "model_b", name: "Model B", percent: 12),
                scoped(id: "model_a", name: nil, percent: 8),
                scoped(id: nil, name: "No id", percent: 5),
                scoped(id: "other", name: "Other", percent: 1, kind: "session"),
            ]
        ))

        #expect(report.windows.map(\.id) == ["weekly", "weekly:model_b", "weekly:model_a"])
        #expect(report.windows.map(\.label) == ["Weekly", "Model B", "model_a"])
        #expect(report.children(of: "weekly").map(\.percentUsed) == [12, 8])
        #expect(report.children(of: "weekly").allSatisfy { $0.windowLength == 7 * 86400 && $0.resetsAt == weeklyReset })
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
            creditGrant: AnthropicOverageCreditGrant(remainingBalance: 7.5, totalGranted: 10, currency: "USD")
        ))

        #expect(report.extras == [
            MoneyRow(id: "overage", label: "Extra usage", amount: Decimal(string: "12.34")!, limit: 50),
            MoneyRow(id: "credits", label: "Extra credits", amount: Decimal(string: "7.5")!, limit: nil),
        ])
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

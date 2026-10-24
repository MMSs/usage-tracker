import Foundation
import Testing
@testable import UsageTracker

@Suite struct ProviderReportTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func reportRoundTripsThroughJSON() throws {
        let report = ProviderReport(
            planName: "Pro",
            windows: [
                LimitWindow(id: "cycle", label: "Cycle", percentUsed: 42.5, resetsAt: date(2026, 11, 1), parentID: nil),
                LimitWindow(id: "auto", label: "Auto", percentUsed: 10, resetsAt: nil, parentID: "cycle"),
            ],
            extras: [MoneyRow(id: "credits", label: "Credits", amount: 12.75, limit: 50)],
            spend: SpendPeriod(
                period: CyclePeriod(start: date(2026, 10, 1), end: date(2026, 11, 1)),
                spent: 7.5,
                limit: 100,
                unit: .dollars,
                daily: [
                    DaySpend(day: date(2026, 10, 1), amount: 3),
                    DaySpend(day: date(2026, 10, 2), amount: 4.5),
                ]
            )
        )

        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(ProviderReport.self, from: data)

        #expect(decoded == report)
    }

    @Test func childrenAreLookedUpByParentID() {
        let report = ProviderReport(
            planName: nil,
            windows: [
                LimitWindow(id: "cycle", label: "Cycle", percentUsed: 50, resetsAt: nil, parentID: nil),
                LimitWindow(id: "auto", label: "Auto", percentUsed: 20, resetsAt: nil, parentID: "cycle"),
                LimitWindow(id: "api", label: "API", percentUsed: 30, resetsAt: nil, parentID: "cycle"),
            ],
            extras: [],
            spend: nil
        )

        #expect(report.children(of: "cycle").map(\.id) == ["auto", "api"])
        #expect(report.children(of: "auto").isEmpty)
        #expect(report.topLevelWindows.map(\.id) == ["cycle"])
    }

    @Test func extrasMatchWindowsByID() {
        let report = ProviderReport(
            planName: nil,
            windows: [LimitWindow(id: "cycle", label: "Included usage", percentUsed: 37, resetsAt: nil, parentID: nil)],
            extras: [
                MoneyRow(id: "cycle", label: "Included usage", amount: 73.5, limit: 200),
                MoneyRow(id: "credits", label: "Credits", amount: 12.5, limit: nil),
            ],
            spend: nil
        )

        #expect(report.extra(for: "cycle")?.amount == 73.5)
        #expect(report.extra(for: "session") == nil)
        #expect(report.standaloneExtras.map(\.id) == ["credits"])
    }

    @Test func windowIsOpenOnlyWithAResetDate() {
        #expect(!LimitWindow(id: "session", label: "Session", percentUsed: 0, resetsAt: nil, parentID: nil).isOpen)
        #expect(LimitWindow(id: "session", label: "Session", percentUsed: 0, resetsAt: date(2026, 10, 24), parentID: nil).isOpen)
    }

    @Test func spentOnADayReadsTheDailySeries() {
        let spend = SpendPeriod(
            period: CyclePeriod(start: date(2026, 10, 1), end: date(2026, 11, 1)),
            spent: 7.5,
            limit: nil,
            unit: .dollars,
            daily: [
                DaySpend(day: date(2026, 10, 1), amount: 3),
                DaySpend(day: date(2026, 10, 2), amount: 4.5),
            ]
        )

        #expect(spend.spent(on: date(2026, 10, 2), calendar: calendar) == 4.5)
        #expect(spend.spent(on: date(2026, 10, 3), calendar: calendar) == 0)
    }

    @Test func budgetUnitFormats() {
        #expect(BudgetUnit.dollars.format(73.5) == "$73.50")
        #expect(BudgetUnit.percent.format(4.25) == "4.3%")
        #expect(BudgetUnit.percent.format(53) == "53%")
    }

    @Test func cachedReportsWithoutWindowLengthDecode() throws {
        let json = #"{"id":"session","label":"Session","percentUsed":12,"resetsAt":1000}"#
        let window = try JSONDecoder().decode(LimitWindow.self, from: Data(json.utf8))

        #expect(window.windowLength == nil)
        #expect(window.resetsAt == Date(timeIntervalSinceReferenceDate: 1000))
    }

    @Test func windowLengthRoundTripsThroughJSON() throws {
        let window = LimitWindow(id: "session", label: "Session", percentUsed: 12, resetsAt: date(2026, 10, 24), parentID: nil, windowLength: 5 * 3600)
        let decoded = try JSONDecoder().decode(LimitWindow.self, from: JSONEncoder().encode(window))

        #expect(decoded == window)
        #expect(decoded.windowLength == TimeInterval(18_000))
    }
}

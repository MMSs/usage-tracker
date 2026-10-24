import Foundation
import Testing
@testable import UsageTracker

@Suite struct CursorReportMapperTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: -8 * 3600)!

        return calendar
    }()

    private func localMidnight(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
    }

    private func usage(_ plan: String, start: String = "2026-10-12", end: String = "2026-11-11", unlimited: Bool = false) throws -> CursorUsageResponse {
        let json = """
        {"billingCycleStart":"\(start)T00:00:00.000Z","billingCycleEnd":"\(end)T00:00:00.000Z","individualUsage":{"plan":\(plan)},"isUnlimited":\(unlimited)}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(CursorUsageResponse.self, from: Data(json.utf8))
    }

    private func apiMilliseconds(_ month: Int, _ day: Int) -> String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = utc.date(from: DateComponents(year: 2026, month: month, day: day))!

        return String(Int64(date.timeIntervalSince1970 * 1000))
    }

    private func map(_ usage: CursorUsageResponse, daily: DailySpendResponse? = nil) -> ProviderReport {
        CursorReportMapper.map(usage: usage, daily: daily, today: localMidnight(10, 20), calendar: calendar)
    }

    @Test func personalPlanMapsPercentWithSplit() throws {
        let report = map(try usage(#"{"used":0,"totalPercentUsed":53,"autoPercentUsed":61,"apiPercentUsed":44}"#))

        #expect(report.windows.map(\.id) == ["cycle", "auto", "api"])
        #expect(report.windows[0].label == "Included usage")
        #expect(report.windows[0].percentUsed == 53)
        #expect(report.windows[0].resetsAt == localMidnight(11, 11))
        #expect(report.windows[1].percentUsed == 61)
        #expect(report.windows[1].label == "Auto")
        #expect(report.windows[1].parentID == "cycle")
        #expect(report.windows[2].percentUsed == 44)
        #expect(report.windows[2].label == "API models")
        #expect(report.spend?.unit == .percent)
        #expect(report.spend?.spent == 53)
        #expect(report.spend?.limit == 100)
        #expect(report.extras.isEmpty)
    }

    @Test func teamPlanMapsDollars() throws {
        let report = map(try usage(#"{"used":7350,"limit":20000}"#))

        #expect(report.windows.map(\.id) == ["cycle"])
        #expect(report.windows[0].percentUsed == 36.75)
        #expect(report.spend?.unit == .dollars)
        #expect(report.spend?.spent == 73.5)
        #expect(report.spend?.limit == 200)
        #expect(report.extras == [MoneyRow(id: "cycle", label: "Included usage", amount: 73.5, limit: 200)])
    }

    @Test func unlimitedPlanHasNoWindow() throws {
        let report = map(try usage(#"{"used":7350}"#, unlimited: true))

        #expect(report.windows.isEmpty)
        #expect(report.extras.count == 1)
        #expect(report.extras[0].limit == nil)
        #expect(report.spend?.limit == nil)
    }

    @Test func usedWithoutLimitOrPercentDoesNotCrash() throws {
        let report = map(try usage(#"{"used":7350}"#))

        #expect(report.windows.map(\.id) == ["cycle"])
        #expect(report.windows[0].percentUsed == 0)
        #expect(report.extras == [MoneyRow(id: "cycle", label: "Included usage", amount: 73.5, limit: nil)])
        #expect(report.spend?.limit == nil)
    }

    @Test func cycleDatesAreDateOnly() throws {
        let report = map(try usage(#"{"used":0}"#))

        #expect(report.spend?.period.start == localMidnight(10, 12))
        #expect(report.spend?.period.end == localMidnight(11, 11))
    }

    @Test func dailySeriesFillsEveryCycleDay() throws {
        let daily = DailySpendResponse(dailySpend: [
            .init(day: apiMilliseconds(10, 14), category: "Auto", spendCents: 150),
            .init(day: apiMilliseconds(10, 14), category: "API", spendCents: 250),
            .init(day: apiMilliseconds(10, 20), spendCents: 1000),
        ])
        let report = map(try usage(#"{"used":1400,"limit":20000}"#), daily: daily)
        let series = try #require(report.spend?.daily)

        #expect(series.count == 30)
        #expect(series.first?.day == localMidnight(10, 12))
        #expect(series.last?.day == localMidnight(11, 10))
        #expect(series.first { $0.day == localMidnight(10, 14) }?.amount == 4)
        #expect(series.first { $0.day == localMidnight(10, 20) }?.amount == 10)
        #expect(series.filter { $0.amount == 0 }.count == 28)
    }

    @Test func percentPlanDailyIsTokenShareOfCyclePercent() throws {
        let daily = DailySpendResponse(dailySpend: [
            .init(day: apiMilliseconds(10, 14), spendCents: 0, totalTokens: "300"),
            .init(day: apiMilliseconds(10, 15), spendCents: 0, totalTokens: "100"),
        ])
        let report = map(try usage(#"{"totalPercentUsed":50}"#), daily: daily)
        let series = try #require(report.spend?.daily)

        #expect(series.count == 30)
        #expect(series.first { $0.day == localMidnight(10, 14) }?.amount == 37.5)
        #expect(series.first { $0.day == localMidnight(10, 15) }?.amount == 12.5)
    }

    @Test func percentPlanWithNoTokensHasZeroDaily() throws {
        let daily = DailySpendResponse(dailySpend: [
            .init(day: apiMilliseconds(10, 14), spendCents: 500),
        ])
        let report = map(try usage(#"{"totalPercentUsed":50}"#), daily: daily)
        let series = try #require(report.spend?.daily)

        #expect(series.count == 30)
        #expect(series.allSatisfy { $0.amount == 0 })
    }

    @Test func missingDailyLeavesEmptySeries() throws {
        let report = map(try usage(#"{"used":100,"limit":20000}"#), daily: nil)

        #expect(report.spend?.daily == [])
    }
}

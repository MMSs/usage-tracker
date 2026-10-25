import Foundation
import Testing
@testable import UsageTracker

@MainActor
struct OpenAICostServiceTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        return calendar
    }()

    private func fixture(_ name: String) throws -> String {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))

        return try String(contentsOf: url, encoding: .utf8)
    }

    private func local(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private var october: CyclePeriod {
        CyclePeriod(start: local(2026, 10, 1), end: local(2026, 11, 1))
    }

    private func queryItems(_ request: URLRequest) -> [String: String] {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []

        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    private func body(values: [String], hasMore: Bool = false, nextPage: String = "null") -> String {
        let results = values.map { "{\"amount\":{\"value\":\($0),\"currency\":\"usd\"}}" }.joined(separator: ",")

        return """
        {"object":"page","data":[{"object":"bucket","start_time":1790812800,"end_time":1790899200,"results":[\(results)]}],"has_more":\(hasMore),"next_page":\(nextPage)}
        """
    }

    @Test func requestCarriesBearerAndUnixRange() async throws {
        let client = RoutingHTTPClient(routes: ["limit=31": .ok(json: body(values: ["1"]))])
        let service = OpenAICostService(client: client)

        _ = try await service.fetchMonthToDate(adminKey: "sk-admin-test", month: october, calendar: calendar)

        let request = try #require(client.requests.first)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        #expect(client.requests.count == 1)
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-admin-test")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "UsageTracker/\(version) (https://github.com/MMSs/usage-tracker)")
        #expect(request.url?.host == "api.openai.com")
        #expect(request.url?.path == "/v1/organization/costs")
        #expect(queryItems(request) == [
            "start_time": "1790812800",
            "end_time": "1793491200",
            "bucket_width": "1d",
            "limit": "31",
        ])
    }

    @Test func pagesAreFollowedAndSummed() async throws {
        let client = RoutingHTTPClient(routes: [
            "limit=31": .ok(json: try fixture("openai-costs-page1")),
            "page=page_2": .ok(json: try fixture("openai-costs-page2")),
        ])
        let service = OpenAICostService(client: client)

        let days = try await service.fetchMonthToDate(adminKey: "k", month: october, calendar: calendar)

        #expect(days == [
            CostDay(day: local(2026, 10, 1), dollars: Decimal(string: "1.26")!),
            CostDay(day: local(2026, 10, 3), dollars: Decimal(string: "2.995")!),
        ])
        #expect(client.requests.count == 2)
        let second = try #require(client.requests.last)
        #expect(queryItems(second)["page"] == "page_2")
        #expect(queryItems(second)["limit"] == "31")
    }

    @Test func amountsKeepDecimalPrecision() async throws {
        let client = RoutingHTTPClient(routes: ["limit=31": .ok(json: body(values: ["0.1", "0.2"]))])
        let service = OpenAICostService(client: client)

        let days = try await service.fetchMonthToDate(adminKey: "k", month: october, calendar: calendar)

        #expect(days.first?.dollars == Decimal(string: "0.3")!)
    }

    @Test func numericStringAmountsAreRead() async throws {
        let client = RoutingHTTPClient(routes: ["limit=31": .ok(json: body(values: ["\"0.25\"", "\"bad\"", "null"]))])
        let service = OpenAICostService(client: client)

        let days = try await service.fetchMonthToDate(adminKey: "k", month: october, calendar: calendar)

        #expect(days == [CostDay(day: local(2026, 10, 1), dollars: Decimal(string: "0.25")!)])
    }

    @Test func repeatedNextPageStopsTheLoop() async throws {
        let page = body(values: ["1"], hasMore: true, nextPage: "\"p1\"")
        let client = RoutingHTTPClient(routes: ["limit=31": .ok(json: page), "page=p1": .ok(json: page)])
        let service = OpenAICostService(client: client)

        let days = try await service.fetchMonthToDate(adminKey: "k", month: october, calendar: calendar)

        #expect(days.count == 1)
        #expect(client.requests.count == 2)
    }

    @Test func nonAdminKeyIsUnauthorized() async throws {
        let client = RoutingHTTPClient(routes: ["limit=31": .status(401, headers: ["Content-Type": "application/json"])])
        let service = OpenAICostService(client: client)

        await #expect(throws: FetchError.unauthorized) {
            try await service.fetchMonthToDate(adminKey: "k", month: october, calendar: calendar)
        }
    }
}

@MainActor
struct OpenAIAPIReportServiceTests {
    private final class StubFetcher: OpenAICostFetching {
        let days: [CostDay]
        private(set) var adminKeys: [String] = []
        private(set) var months: [CyclePeriod] = []

        init(days: [CostDay]) {
            self.days = days
        }

        func fetchMonthToDate(adminKey: String, month: CyclePeriod, calendar: Calendar) async throws -> [CostDay] {
            adminKeys.append(adminKey)
            months.append(month)

            return days
        }
    }

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        return calendar
    }()

    private func local(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func apiReportUsesTheSharedMonth() async throws {
        let days = [CostDay(day: local(2026, 10, 1), dollars: Decimal(string: "1.26")!)]
        let fetcher = StubFetcher(days: days)
        let service = OpenAIAPIReportService(service: fetcher, calendar: calendar)
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 15))!

        let report = try await service.fetchReport(credentials: ["admin-key": "sk-admin-test"], today: today)

        let month = try APISpend.month(containing: today, calendar: calendar)
        #expect(fetcher.adminKeys == ["sk-admin-test"])
        #expect(fetcher.months == [month])
        #expect(report == APISpend.report(days: days, month: month, today: today, calendar: calendar))
    }

    @Test func missingAdminKeyIsUnauthorized() async {
        let fetcher = StubFetcher(days: [])
        let service = OpenAIAPIReportService(service: fetcher, calendar: calendar)

        await #expect(throws: FetchError.unauthorized) {
            try await service.fetchReport(credentials: [:], today: Date())
        }
        #expect(fetcher.adminKeys.isEmpty)
    }
}

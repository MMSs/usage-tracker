import Foundation
import Testing
@testable import UsageTracker

@MainActor
struct AnthropicCostServiceTests {
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

    private func page(starting: String, amounts: [String], hasMore: Bool, nextPage: String?) -> String {
        let results = amounts.map { "{\"currency\":\"USD\",\"amount\":\"\($0)\"}" }.joined(separator: ",")
        let next = nextPage.map { "\"\($0)\"" } ?? "null"

        return """
        {"data":[{"starting_at":"\(starting)","ending_at":"\(starting)","results":[\(results)]}],"has_more":\(hasMore),"next_page":\(next)}
        """
    }

    private func queryItems(_ request: URLRequest) -> [String: String] {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []

        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test func requestCarriesAdminHeadersAndMonthRange() async throws {
        let client = RoutingHTTPClient(routes: ["limit=31": .ok(json: try fixture("anthropic-cost-report"))])
        let service = AnthropicCostService(client: client)

        _ = try await service.fetchMonthToDate(adminKey: "sk-ant-admin-test", month: october, calendar: calendar)

        let request = try #require(client.requests.first)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        #expect(client.requests.count == 1)
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant-admin-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "UsageTracker/\(version) (https://github.com/MMSs/usage-tracker)")
        #expect(request.url?.host == "api.anthropic.com")
        #expect(request.url?.path == "/v1/organizations/cost_report")
        #expect(queryItems(request) == [
            "starting_at": "2026-10-01T00:00:00Z",
            "ending_at": "2026-11-01T00:00:00Z",
            "bucket_width": "1d",
            "limit": "31",
        ])
    }

    @Test func centsBecomeDollarsAndPagesAreSummed() async throws {
        let client = RoutingHTTPClient(routes: [
            "limit=31": .ok(json: page(starting: "2026-10-01T00:00:00Z", amounts: ["100", "50.5"], hasMore: true, nextPage: "p2")),
            "page=p2": .ok(json: page(starting: "2026-10-02T00:00:00Z", amounts: ["2000"], hasMore: false, nextPage: nil)),
        ])
        let service = AnthropicCostService(client: client)

        let days = try await service.fetchMonthToDate(adminKey: "k", month: october, calendar: calendar)

        #expect(days == [
            AnthropicCostDay(day: local(2026, 10, 1), dollars: Decimal(string: "1.505")!),
            AnthropicCostDay(day: local(2026, 10, 2), dollars: 20),
        ])
        #expect(client.requests.count == 2)
        let second = try #require(client.requests.last)
        #expect(second.url?.query?.hasSuffix("page=p2") == true)
        #expect(queryItems(second)["limit"] == "31")
    }

    @Test func fixtureYieldsExactDollarsAndOmitsEmptyDays() async throws {
        let client = RoutingHTTPClient(routes: ["limit=31": .ok(json: try fixture("anthropic-cost-report"))])
        let service = AnthropicCostService(client: client)

        let days = try await service.fetchMonthToDate(adminKey: "k", month: october, calendar: calendar)

        #expect(days == [
            AnthropicCostDay(day: local(2026, 10, 1), dollars: Decimal(string: "12.345678")!),
            AnthropicCostDay(day: local(2026, 10, 3), dollars: Decimal(string: "2.995")!),
        ])
    }

    @Test func sameDayAcrossPagesIsSummed() async throws {
        let client = RoutingHTTPClient(routes: [
            "limit=31": .ok(json: page(starting: "2026-10-05T00:00:00Z", amounts: ["100"], hasMore: true, nextPage: "p2")),
            "page=p2": .ok(json: page(starting: "2026-10-05T00:00:00Z", amounts: ["250"], hasMore: false, nextPage: nil)),
        ])
        let service = AnthropicCostService(client: client)

        let days = try await service.fetchMonthToDate(adminKey: "k", month: october, calendar: calendar)

        #expect(days == [AnthropicCostDay(day: local(2026, 10, 5), dollars: Decimal(string: "3.5")!)])
    }

    @Test func bucketDatesMapToLocalCalendarDays() async throws {
        let client = RoutingHTTPClient(routes: [
            "limit=31": .ok(json: page(starting: "2026-10-03T00:00:00Z", amounts: ["100"], hasMore: false, nextPage: nil)),
        ])
        let service = AnthropicCostService(client: client)

        let days = try await service.fetchMonthToDate(adminKey: "k", month: october, calendar: calendar)

        // 00:00Z on 3 Oct is still 2 Oct in Los Angeles; the bucket belongs to 3 Oct.
        #expect(days.first?.day == calendar.startOfDay(for: local(2026, 10, 3)))
        #expect(calendar.component(.day, from: try #require(days.first?.day)) == 3)
    }

    @Test func fractionalSecondBucketDatesAreAccepted() async throws {
        let client = RoutingHTTPClient(routes: [
            "limit=31": .ok(json: page(starting: "2026-10-03T00:00:00.000Z", amounts: ["100"], hasMore: false, nextPage: nil)),
        ])
        let service = AnthropicCostService(client: client)

        let days = try await service.fetchMonthToDate(adminKey: "k", month: october, calendar: calendar)

        #expect(days == [AnthropicCostDay(day: local(2026, 10, 3), dollars: 1)])
    }

    @Test(arguments: ["null", "\"p1\""])
    func brokenPaginationStopsInsteadOfLooping(nextPage: String) async throws {
        // Page 1 is also what "page=p1" resolves to, so a repeated token would loop forever.
        let body = """
        {"data":[{"starting_at":"2026-10-01T00:00:00Z","ending_at":"2026-10-02T00:00:00Z","results":[{"amount":"100"}]}],"has_more":true,"next_page":\(nextPage)}
        """
        let client = RoutingHTTPClient(routes: ["limit=31": .ok(json: body), "page=p1": .ok(json: body)])
        let service = AnthropicCostService(client: client)

        let days = try await service.fetchMonthToDate(adminKey: "k", month: october, calendar: calendar)

        #expect(days.count == 1)
        #expect(client.requests.count <= 2)
    }

    @Test func individualAccountForbiddenIsUnauthorized() async throws {
        let client = RoutingHTTPClient(routes: ["limit=31": .status(403, headers: ["Content-Type": "application/json"])])
        let service = AnthropicCostService(client: client)

        await #expect(throws: FetchError.unauthorized) {
            try await service.fetchMonthToDate(adminKey: "k", month: october, calendar: calendar)
        }
    }

    @Test func unparseableAmountIsADecodingError() async throws {
        let client = RoutingHTTPClient(routes: [
            "limit=31": .ok(json: page(starting: "2026-10-01T00:00:00Z", amounts: ["12,5"], hasMore: false, nextPage: nil)),
        ])
        let service = AnthropicCostService(client: client)

        await #expect(throws: FetchError.decoding) {
            try await service.fetchMonthToDate(adminKey: "k", month: october, calendar: calendar)
        }
    }

    @Test func malformedBodyIsADecodingError() async throws {
        let client = RoutingHTTPClient(routes: ["limit=31": .ok(json: "not json")])
        let service = AnthropicCostService(client: client)

        await #expect(throws: FetchError.decoding) {
            try await service.fetchMonthToDate(adminKey: "k", month: october, calendar: calendar)
        }
    }
}

@MainActor
struct AnthropicAPIReportServiceTests {
    private final class StubFetcher: AnthropicCostFetching {
        let days: [AnthropicCostDay]
        private(set) var adminKeys: [String] = []
        private(set) var months: [CyclePeriod] = []

        init(days: [AnthropicCostDay]) {
            self.days = days
        }

        func fetchMonthToDate(adminKey: String, month: CyclePeriod, calendar: Calendar) async throws -> [AnthropicCostDay] {
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

    @Test func missingAdminKeyIsUnauthorized() async {
        let fetcher = StubFetcher(days: [])
        let service = AnthropicAPIReportService(service: fetcher, calendar: calendar)

        await #expect(throws: FetchError.unauthorized) {
            try await service.fetchReport(credentials: [:], today: Date())
        }
        #expect(fetcher.adminKeys.isEmpty)
    }

    @Test func apiReportSumsTheMonth() async throws {
        let days = [
            AnthropicCostDay(day: local(2026, 10, 1), dollars: Decimal(string: "12.345678")!),
            AnthropicCostDay(day: local(2026, 10, 3), dollars: Decimal(string: "2.995")!),
        ]
        let fetcher = StubFetcher(days: days)
        let service = AnthropicAPIReportService(service: fetcher, calendar: calendar)
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 15))!

        let report = try await service.fetchReport(credentials: ["admin-key": "sk-ant-admin-test"], today: today)

        let month = CyclePeriod(start: local(2026, 10, 1), end: local(2026, 11, 1))
        #expect(fetcher.adminKeys == ["sk-ant-admin-test"])
        #expect(fetcher.months == [month])
        #expect(report == AnthropicReportMapper.api(days: days, month: month))
        #expect(report.spend?.spent == Decimal(string: "15.340678"))
    }
}

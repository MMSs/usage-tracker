import Foundation
import os

@MainActor
protocol AnthropicCostFetching {
    /// `today` says whether the month has a whole UTC day to report yet.
    func fetchMonthToDate(adminKey: String, month: CyclePeriod, today: Date, calendar: Calendar) async throws -> [CostDay]
}

final class AnthropicCostService: AnthropicCostFetching {
    private static let endpoint = "https://api.anthropic.com/v1/organizations/cost_report"

    private let client: HTTPClient

    init(client: HTTPClient = URLSessionHTTPClient()) {
        self.client = client
    }

    func fetchMonthToDate(adminKey: String, month: CyclePeriod, today: Date, calendar: Calendar) async throws -> [CostDay] {
        // The API reports whole UTC days only and clamps `ending_at` to the
        // start of the current one. On the month's first UTC day that leaves
        // an empty range, which it refuses all day with a 400 ("ending date
        // must be after starting date"); there is nothing to ask for yet.
        guard let firstDayEnd = Self.utc.date(byAdding: .day, value: 1, to: Self.utcMidnightDate(of: month.start, in: calendar)),
              today >= firstDayEnd
        else {
            Log.http.info("cost_report not requested: the month's first UTC day has not ended")
            return []
        }

        let baseQuery = [
            ("starting_at", Self.utcMidnight(of: month.start, in: calendar)),
            ("ending_at", Self.utcMidnight(of: month.end, in: calendar)),
            ("bucket_width", "1d"),
            ("limit", "31"),
        ]
        var query = baseQuery
        var totals: [Date: Decimal] = [:]
        var seenPages: Set<String> = []

        while true {
            let data = try await HTTPResponseHandler.data(
                for: request(query: query, adminKey: adminKey),
                client: client
            )
            let page = try decode(data)

            for bucket in page.data {
                // A null amount is no cost; a day with nothing else is omitted like an empty one.
                let amounts = bucket.results.compactMap(\.amount)
                guard !amounts.isEmpty else {
                    continue
                }

                let day = try CostDay.localDay(ofUTC: bucket.startingAt, calendar: calendar)
                let cents = try amounts.reduce(Decimal(0)) { try $0 + Self.cents($1) }
                totals[day, default: 0] += cents / 100
            }

            // A server that says "more" without a fresh token would loop forever.
            guard page.hasMore,
                  let next = page.nextPage, !next.isEmpty,
                  seenPages.insert(next).inserted
            else {
                break
            }

            query = baseQuery + [("page", next)]
        }

        return totals
            .map { CostDay(day: $0.key, dollars: $0.value) }
            .sorted { $0.day < $1.day }
    }

    private func decode(_ data: Data) throws -> AnthropicCostReportResponse {
        // The default decoder cannot read the ISO 8601 bucket dates.
        do {
            return try AnthropicUsageResponse.decoder().decode(AnthropicCostReportResponse.self, from: data)
        } catch {
            HTTPResponseHandler.logDecodingFailure(error, decoding: AnthropicCostReportResponse.self)
            throw FetchError.decoding
        }
    }

    private static func cents(_ amount: String) throws -> Decimal {
        guard let value = RequestSupport.decimal(fromNumericString: amount)
        else {
            Log.http.error("cost_report amount is not a decimal number")
            throw FetchError.decoding
        }

        return value
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        return calendar
    }()

    /// `YYYY-MM-DDT00:00:00Z` for the calendar date `date` falls on in `calendar`.
    private static func utcMidnight(of date: Date, in calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)

        return String(format: "%04d-%02d-%02dT00:00:00Z", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// UTC midnight of the calendar date `date` falls on in `calendar`.
    private static func utcMidnightDate(of date: Date, in calendar: Calendar) -> Date {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)

        return utc.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day)) ?? date
    }

    private func request(query: [(name: String, value: String)], adminKey: String) -> URLRequest {
        let encoded = RequestSupport.encodedQuery(query)
        var request = URLRequest(url: URL(string: "\(Self.endpoint)?\(encoded)")!)
        request.httpMethod = "GET"
        request.setValue(adminKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(RequestSupport.userAgent, forHTTPHeaderField: "User-Agent")

        return request
    }
}

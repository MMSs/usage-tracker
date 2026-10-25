import Foundation
import os

@MainActor
protocol AnthropicCostFetching {
    func fetchMonthToDate(adminKey: String, month: CyclePeriod, calendar: Calendar) async throws -> [CostDay]
}

final class AnthropicCostService: AnthropicCostFetching {
    private static let endpoint = "https://api.anthropic.com/v1/organizations/cost_report"

    private let client: HTTPClient

    init(client: HTTPClient = URLSessionHTTPClient()) {
        self.client = client
    }

    func fetchMonthToDate(adminKey: String, month: CyclePeriod, calendar: Calendar) async throws -> [CostDay] {
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

    /// `YYYY-MM-DDT00:00:00Z` for the calendar date `date` falls on in `calendar`.
    private static func utcMidnight(of date: Date, in calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)

        return String(format: "%04d-%02d-%02dT00:00:00Z", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
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

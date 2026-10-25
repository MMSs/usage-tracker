import Foundation
import os

@MainActor
protocol OpenAICostFetching {
    func fetchMonthToDate(adminKey: String, month: CyclePeriod, calendar: Calendar) async throws -> [CostDay]
}

final class OpenAICostService: OpenAICostFetching {
    private static let endpoint = "https://api.openai.com/v1/organization/costs"
    /// RFC 3986 unreserved characters; everything else in a query value is escaped.
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private let client: HTTPClient

    init(client: HTTPClient = URLSessionHTTPClient()) {
        self.client = client
    }

    func fetchMonthToDate(adminKey: String, month: CyclePeriod, calendar: Calendar) async throws -> [CostDay] {
        let baseQuery = [
            ("start_time", Self.utcMidnight(of: month.start, in: calendar)),
            ("end_time", Self.utcMidnight(of: month.end, in: calendar)),
            ("bucket_width", "1d"),
            ("limit", "31"),
        ]
        var query = baseQuery
        var totals: [Date: Decimal] = [:]
        var seenPages: Set<String> = []
        var skipped = false

        while true {
            let data = try await HTTPResponseHandler.data(
                for: request(query: query, adminKey: adminKey),
                client: client
            )
            let page = try decode(data)

            for bucket in page.data {
                skipped = skipped || bucket.results.contains { $0.amount == nil }

                // A day with nothing readable is omitted like an empty one.
                let amounts = bucket.results.compactMap(\.amount)
                guard !amounts.isEmpty else {
                    continue
                }

                let day = try CostDay.localDay(ofUTC: bucket.startTime, calendar: calendar)
                totals[day, default: 0] += amounts.reduce(0, +)
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

        if skipped {
            Log.http.error("costs results without a readable amount were skipped")
        }

        return totals
            .map { CostDay(day: $0.key, dollars: $0.value) }
            .sorted { $0.day < $1.day }
    }

    private func decode(_ data: Data) throws -> OpenAICostsResponse {
        do {
            return try JSONDecoder().decode(OpenAICostsResponse.self, from: data)
        } catch {
            HTTPResponseHandler.logDecodingFailure(error, decoding: OpenAICostsResponse.self)
            throw FetchError.decoding
        }
    }

    /// Unix seconds of UTC midnight of the calendar date `date` falls on in `calendar`.
    private static func utcMidnight(of date: Date, in calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let midnight = utc.date(from: parts) ?? date

        return String(Int(midnight.timeIntervalSince1970))
    }

    private func request(query: [(name: String, value: String)], adminKey: String) -> URLRequest {
        let encoded = query
            .map { "\($0.name)=\($0.value.addingPercentEncoding(withAllowedCharacters: Self.unreserved) ?? "")" }
            .joined(separator: "&")
        var request = URLRequest(url: URL(string: "\(Self.endpoint)?\(encoded)")!)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        request.httpMethod = "GET"
        request.setValue("Bearer \(adminKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("UsageTracker/\(version) (https://github.com/MMSs/usage-tracker)", forHTTPHeaderField: "User-Agent")

        return request
    }
}

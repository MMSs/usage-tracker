import Foundation

struct AnthropicCostDay: Equatable {
    /// Local midnight of the bucket's UTC calendar date.
    let day: Date
    /// Full precision; formatting rounds later.
    let dollars: Decimal
}

@MainActor
protocol AnthropicCostFetching {
    func fetchMonthToDate(adminKey: String, month: CyclePeriod, calendar: Calendar) async throws -> [AnthropicCostDay]
}

final class AnthropicCostService: AnthropicCostFetching {
    private static let endpoint = "https://api.anthropic.com/v1/organizations/cost_report"
    private static let posix = Locale(identifier: "en_US_POSIX")
    /// RFC 3986 unreserved characters; everything else in a query value is escaped.
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private let client: HTTPClient

    init(client: HTTPClient = URLSessionHTTPClient()) {
        self.client = client
    }

    func fetchMonthToDate(adminKey: String, month: CyclePeriod, calendar: Calendar) async throws -> [AnthropicCostDay] {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!

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

            for bucket in page.data where !bucket.results.isEmpty {
                let day = try Self.localDay(of: bucket.startingAt, utc: utc, calendar: calendar)
                let cents = try bucket.results.reduce(Decimal(0)) { try $0 + Self.cents($1.amount) }
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
            .map { AnthropicCostDay(day: $0.key, dollars: $0.value) }
            .sorted { $0.day < $1.day }
    }

    private func decode(_ data: Data) throws -> AnthropicCostReportResponse {
        // The default decoder cannot read the ISO 8601 bucket dates.
        do {
            return try AnthropicUsageResponse.decoder().decode(AnthropicCostReportResponse.self, from: data)
        } catch {
            throw FetchError.decoding
        }
    }

    private static func cents(_ amount: String) throws -> Decimal {
        // `Decimal(string:)` stops at the first bad character, so "12,5" would read as 12.
        guard amount.range(of: #"^[+-]?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: amount, locale: posix)
        else {
            throw FetchError.decoding
        }

        return value
    }

    /// `YYYY-MM-DDT00:00:00Z` for the calendar date `date` falls on in `calendar`.
    private static func utcMidnight(of date: Date, in calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)

        return String(format: "%04d-%02d-%02dT00:00:00Z", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The bucket's UTC calendar date, as local midnight.
    private static func localDay(of date: Date, utc: Calendar, calendar: Calendar) throws -> Date {
        let parts = utc.dateComponents([.year, .month, .day], from: date)
        guard let day = calendar.date(from: parts) else {
            throw FetchError.decoding
        }

        return day
    }

    private func request(query: [(name: String, value: String)], adminKey: String) -> URLRequest {
        let encoded = query
            .map { "\($0.name)=\($0.value.addingPercentEncoding(withAllowedCharacters: Self.unreserved) ?? "")" }
            .joined(separator: "&")
        var request = URLRequest(url: URL(string: "\(Self.endpoint)?\(encoded)")!)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        request.httpMethod = "GET"
        request.setValue(adminKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("UsageTracker/\(version) (https://github.com/MMSs/usage-tracker)", forHTTPHeaderField: "User-Agent")

        return request
    }
}

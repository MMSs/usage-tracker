import Foundation

@MainActor
final class AnthropicAPIReportService: ReportFetching {
    private let service: AnthropicCostFetching
    private let calendar: Calendar

    init(service: AnthropicCostFetching, calendar: Calendar = .current) {
        self.service = service
        self.calendar = calendar
    }

    func fetchReport(credentials: [String: String], today: Date) async throws -> ProviderReport {
        guard let adminKey = credentials["admin-key"] else {
            throw FetchError.unauthorized
        }

        let month = try monthPeriod(containing: today)
        let days = try await service.fetchMonthToDate(adminKey: adminKey, month: month, calendar: calendar)

        return AnthropicReportMapper.api(days: days, month: month)
    }

    /// The Admin API buckets by UTC day, so the month is the UTC calendar
    /// month containing `today`; its bounds are local midnights of that
    /// month's first day and the next month's first day. `end` is exclusive.
    private func monthPeriod(containing today: Date) throws -> CyclePeriod {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!

        let parts = utc.dateComponents([.year, .month], from: today)
        guard let year = parts.year, let month = parts.month,
              let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let end = calendar.date(from: DateComponents(
                  year: month == 12 ? year + 1 : year,
                  month: month == 12 ? 1 : month + 1,
                  day: 1
              ))
        else {
            throw FetchError.decoding
        }

        return CyclePeriod(start: start, end: end)
    }
}

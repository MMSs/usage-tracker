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

        // `end` is the start of next month, exclusive.
        guard let interval = calendar.dateInterval(of: .month, for: today) else {
            throw FetchError.decoding
        }

        let month = CyclePeriod(start: interval.start, end: interval.end)
        let days = try await service.fetchMonthToDate(adminKey: adminKey, month: month, calendar: calendar)

        return AnthropicReportMapper.api(days: days, month: month)
    }
}

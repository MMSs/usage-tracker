import Foundation

@MainActor
final class OpenAIAPIReportService: ReportFetching {
    private let service: OpenAICostFetching
    private let calendar: Calendar

    init(service: OpenAICostFetching, calendar: Calendar = .current) {
        self.service = service
        self.calendar = calendar
    }

    func fetchReport(credentials: [String: String], today: Date) async throws -> ProviderReport {
        guard let adminKey = credentials["admin-key"] else {
            throw FetchError.unauthorized
        }

        let month = try APISpend.month(containing: today, calendar: calendar)
        let days = try await service.fetchMonthToDate(adminKey: adminKey, month: month, calendar: calendar)

        return APISpend.report(days: days, month: month, today: today, calendar: calendar)
    }
}

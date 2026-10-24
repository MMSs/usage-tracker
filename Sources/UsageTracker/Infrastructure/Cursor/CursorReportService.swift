import Foundation

@MainActor
final class CursorReportService: ReportFetching {
    private let service: CursorUsageService

    init(service: CursorUsageService) {
        self.service = service
    }

    func fetchReport(credentials: [String: String], today: Date) async throws -> ProviderReport {
        guard let token = credentials["session-token"] else {
            throw FetchError.unauthorized
        }

        let usage = try await service.fetchUsage(token: token)
        let calendar = Calendar.current
        let probe = CursorReportMapper.map(usage: usage, daily: nil, today: today, calendar: calendar)

        var daily: DailySpendResponse?
        if let period = probe.spend?.period {
            daily = try? await service.fetchDailySpend(token: token, periodStart: period.start, periodEnd: period.end)
        }

        return CursorReportMapper.map(usage: usage, daily: daily, today: today, calendar: calendar)
    }
}

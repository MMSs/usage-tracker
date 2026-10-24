import Foundation

@MainActor
final class CursorReportService: ReportFetching {
    private let usage: UsageFetching
    private let daily: DailySpendFetching

    init(usage: UsageFetching, daily: DailySpendFetching) {
        self.usage = usage
        self.daily = daily
    }

    convenience init(service: CursorUsageService) {
        self.init(usage: service, daily: service)
    }

    func fetchReport(credentials: [String: String], today: Date) async throws -> ProviderReport {
        guard let token = credentials["session-token"] else {
            throw FetchError.unauthorized
        }

        let usageResponse = try await usage.fetchUsage(token: token)
        let calendar = Calendar.current
        let probe = CursorReportMapper.map(usage: usageResponse, daily: nil, today: today, calendar: calendar)

        var dailyResponse: DailySpendResponse?
        if let period = probe.spend?.period {
            do {
                dailyResponse = try await daily.fetchDailySpend(token: token, periodStart: period.start, periodEnd: period.end)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                dailyResponse = nil
            }
        }

        return CursorReportMapper.map(usage: usageResponse, daily: dailyResponse, today: today, calendar: calendar)
    }
}

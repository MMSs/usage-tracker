import Foundation
import Testing
@testable import UsageTracker

@MainActor
struct CursorReportServiceTests {
    private struct StubUsage: UsageFetching {
        func fetchUsage(token: String) async throws -> CursorUsageResponse {
            let json = """
            {"billingCycleStart":"2026-10-12T00:00:00.000Z","billingCycleEnd":"2026-11-11T00:00:00.000Z","individualUsage":{"plan":{"used":7350,"limit":20000}},"isUnlimited":false}
            """
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            return try decoder.decode(CursorUsageResponse.self, from: Data(json.utf8))
        }
    }

    private struct FailingDaily: DailySpendFetching {
        let error: any Error

        func fetchDailySpend(token: String, periodStart: Date, periodEnd: Date) async throws -> DailySpendResponse {
            throw error
        }

        func membershipStart(token: String) async throws -> Date? {
            nil
        }
    }

    private func service(dailyError: any Error) -> CursorReportService {
        CursorReportService(usage: StubUsage(), daily: FailingDaily(error: dailyError))
    }

    @Test func cancellationDuringDailyFetchPropagates() async {
        let service = service(dailyError: CancellationError())

        await #expect(throws: CancellationError.self) {
            try await service.fetchReport(credentials: ["session-token": "t"], today: Date(timeIntervalSince1970: 1_792_000_000))
        }
    }

    @Test func dailyFetchFailureStillReturnsUsage() async throws {
        let service = service(dailyError: FetchError.httpStatus(500))

        let report = try await service.fetchReport(credentials: ["session-token": "t"], today: Date(timeIntervalSince1970: 1_792_000_000))

        #expect(report.spend?.spent == 73.5)
        #expect(report.spend?.daily.isEmpty == true)
    }
}

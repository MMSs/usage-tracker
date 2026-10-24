import Foundation

@MainActor
final class AnthropicSubscriptionReportService: ReportFetching {
    private let service: AnthropicUsageFetching

    init(service: AnthropicUsageFetching) {
        self.service = service
    }

    func fetchReport(credentials: [String: String], today: Date) async throws -> ProviderReport {
        guard let sessionKey = credentials["session-key"] else {
            throw FetchError.unauthorized
        }

        return AnthropicReportMapper.subscription(try await service.fetchSubscription(sessionKey: sessionKey))
    }
}

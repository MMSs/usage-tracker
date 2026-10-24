import Foundation
import Testing
@testable import UsageTracker

@MainActor
struct AnthropicSubscriptionReportServiceTests {
    private final class StubFetcher: AnthropicUsageFetching {
        let snapshot: AnthropicSubscriptionSnapshot
        private(set) var sessionKeys: [String] = []

        init(snapshot: AnthropicSubscriptionSnapshot) {
            self.snapshot = snapshot
        }

        func fetchSubscription(sessionKey: String) async throws -> AnthropicSubscriptionSnapshot {
            sessionKeys.append(sessionKey)
            return snapshot
        }
    }

    private let snapshot = AnthropicSubscriptionSnapshot(
        usage: AnthropicUsageResponse(
            fiveHour: .init(utilization: 42, resetsAt: nil),
            sevenDay: nil,
            limits: [],
            legacyModelWindows: [:]
        ),
        planName: "Pro",
        spendLimit: nil,
        creditGrant: nil
    )

    @Test func missingSessionKeyIsUnauthorized() async {
        let fetcher = StubFetcher(snapshot: snapshot)
        let service = AnthropicSubscriptionReportService(service: fetcher)

        await #expect(throws: FetchError.unauthorized) {
            try await service.fetchReport(credentials: [:], today: Date())
        }
        #expect(fetcher.sessionKeys.isEmpty)
    }

    @Test func reportComesFromTheMapper() async throws {
        let fetcher = StubFetcher(snapshot: snapshot)
        let service = AnthropicSubscriptionReportService(service: fetcher)

        let report = try await service.fetchReport(credentials: ["session-key": "k"], today: Date())

        #expect(report == AnthropicReportMapper.subscription(snapshot))
        #expect(fetcher.sessionKeys == ["k"])
    }
}

import Foundation
import Testing
@testable import UsageTracker

@MainActor
struct AnthropicSubscriptionReportServiceTests {
    private final class StubFetcher: AnthropicUsageFetching {
        let snapshot: AnthropicSubscriptionSnapshot
        var error: FetchError?
        var listed: [String: [AnthropicOrganizationsResponse.Organization]] = [:]
        private(set) var sessionKeys: [String] = []
        private(set) var organizationIDs: [String?] = []

        init(snapshot: AnthropicSubscriptionSnapshot) {
            self.snapshot = snapshot
        }

        func organizations(sessionKey: String) -> [AnthropicOrganizationsResponse.Organization] {
            listed[sessionKey] ?? []
        }

        func fetchSubscription(sessionKey: String, organizationID: String?) async throws -> AnthropicSubscriptionSnapshot {
            sessionKeys.append(sessionKey)
            organizationIDs.append(organizationID)
            if let error {
                throw error
            }
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

    private let selections = MemoryOrganizationSelectionStore()

    private func makeService(_ fetcher: StubFetcher) -> AnthropicSubscriptionReportService {
        AnthropicSubscriptionReportService(service: fetcher, selectionStore: selections)
    }

    private static let listed: [AnthropicOrganizationsResponse.Organization] = [
        .init(uuid: "org-a", name: "Personal"),
        .init(uuid: "org-b", name: nil),
    ]

    @Test func missingSessionKeyIsUnauthorized() async {
        let fetcher = StubFetcher(snapshot: snapshot)
        let service = makeService(fetcher)

        await #expect(throws: FetchError.unauthorized) {
            try await service.fetchReport(credentials: [:], today: Date())
        }
        #expect(fetcher.sessionKeys.isEmpty)
    }

    @Test func reportComesFromTheMapper() async throws {
        let fetcher = StubFetcher(snapshot: snapshot)
        let service = makeService(fetcher)

        let today = Date()
        let report = try await service.fetchReport(credentials: ["session-key": "k"], today: today)

        #expect(report == AnthropicReportMapper.subscription(snapshot, now: today))
        #expect(fetcher.sessionKeys == ["k"])
        #expect(fetcher.organizationIDs == [nil])
    }

    @Test func theStoredChoiceIsFetched() async throws {
        let fetcher = StubFetcher(snapshot: snapshot)
        selections.selections[.anthropic] = "org-b"
        let service = makeService(fetcher)

        _ = try await service.fetchReport(credentials: ["session-key": "k"], today: Date())

        #expect(service.selectedOrganizationID == "org-b")
        #expect(fetcher.organizationIDs == ["org-b"])
    }

    @Test func organizationsListedForTheKeyAreKnownEvenWhenAChoiceIsNeeded() async {
        let fetcher = StubFetcher(snapshot: snapshot)
        fetcher.listed = ["k": Self.listed, "other": [.init(uuid: "org-z")]]
        fetcher.error = .needsOrganizationChoice
        let service = makeService(fetcher)
        #expect(service.organizations.isEmpty)

        await #expect(throws: FetchError.needsOrganizationChoice) {
            try await service.fetchReport(credentials: ["session-key": "k"], today: Date())
        }

        #expect(service.organizations == [
            AccountOrganization(id: "org-a", name: "Personal"),
            AccountOrganization(id: "org-b", name: nil),
        ])
    }

    @Test func organizationsCarryAPlanOrAPIDetail() async throws {
        let fetcher = StubFetcher(snapshot: snapshot)
        fetcher.listed = ["k": [
            .init(uuid: "chat", name: "sam's Organization", rateLimitTier: "default_claude_max_20x", capabilities: ["chat", "claude_max"]),
            .init(uuid: "console", name: "sam's Organization", capabilities: ["api"]),
        ]]
        let service = makeService(fetcher)

        _ = try await service.fetchReport(credentials: ["session-key": "k"], today: Date())

        #expect(service.organizations.map(\.detail) == ["Max 20x", "API"])
    }

    @Test func choosingStoresTheChoiceAndResettingForgetsItAndTheList() async throws {
        let fetcher = StubFetcher(snapshot: snapshot)
        fetcher.listed = ["k": Self.listed]
        let service = makeService(fetcher)
        _ = try await service.fetchReport(credentials: ["session-key": "k"], today: Date())

        service.selectOrganization("org-a")
        #expect(selections.selections[.anthropic] == "org-a")
        #expect(service.selectedOrganizationID == "org-a")

        service.resetOrganizations()
        #expect(selections.selections[.anthropic] == nil)
        #expect(service.selectedOrganizationID == nil)
        #expect(service.organizations.isEmpty)
    }
}

struct AccountOrganizationTests {
    @Test func labelsAddTheDetailAndTheIDPrefixOnlyWhenLabelsStillCollide() {
        let organizations = [
            AccountOrganization(id: "aaaaaaaa-1", name: "sam's Organization", detail: "Max 20x"),
            AccountOrganization(id: "bbbbbbbb-2", name: "sam's Organization", detail: "API"),
            AccountOrganization(id: "cccccccc-3", name: "Acme", detail: nil),
            AccountOrganization(id: "dddddddd-4", name: "Twin", detail: "Pro"),
            AccountOrganization(id: "eeeeeeee-5", name: "Twin", detail: "Pro"),
        ]

        #expect(AccountOrganization.labels(for: organizations) == [
            "aaaaaaaa-1": "sam's Organization · Max 20x",
            "bbbbbbbb-2": "sam's Organization · API",
            "cccccccc-3": "Acme",
            "dddddddd-4": "Twin · Pro · dddddddd",
            "eeeeeeee-5": "Twin · Pro · eeeeeeee",
        ])
    }

    @Test func organizationDetailNamesThePlanOrAPI() {
        typealias Organization = AnthropicOrganizationsResponse.Organization
        #expect(Organization(uuid: "a", capabilities: ["api"]).detail == "API")
        #expect(Organization(uuid: "a", rateLimitTier: "default_claude_max_5x", capabilities: ["chat", "claude_max"]).detail == "Max 5x")
        #expect(Organization(uuid: "a", rateLimitTier: "default_claude_pro").detail == "Pro")
        #expect(Organization(uuid: "a", capabilities: ["chat"]).detail == nil)
        #expect(Organization(uuid: "a").detail == nil)
    }

    @Test func namelessOrganizationsAreTitledByTheirIDPrefix() {
        #expect(AccountOrganization(id: "3f1c2a9e-7b4d-4e8a-9c61-0d2f5b8a7e14", name: "Team").title == "Team")
        #expect(AccountOrganization(id: "3f1c2a9e-7b4d-4e8a-9c61-0d2f5b8a7e14", name: nil).title == "3f1c2a9e")
        #expect(AccountOrganization(id: "3f1c2a9e-7b4d-4e8a-9c61-0d2f5b8a7e14", name: "  ").title == "3f1c2a9e")
    }
}

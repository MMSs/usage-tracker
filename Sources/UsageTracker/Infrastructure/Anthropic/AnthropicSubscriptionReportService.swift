import Foundation

@MainActor
final class AnthropicSubscriptionReportService: ReportFetching, OrganizationScopedFetching, SessionStarting {
    private static let provider = Provider.anthropic

    private let service: AnthropicUsageFetching
    private let selectionStore: OrganizationSelectionStoring
    private let models: SessionModelStoring
    private(set) var organizations: [AccountOrganization] = []

    init(service: AnthropicUsageFetching, selectionStore: OrganizationSelectionStoring, models: SessionModelStoring) {
        self.service = service
        self.selectionStore = selectionStore
        self.models = models
    }

    var selectedOrganizationID: String? {
        selectionStore.selectedOrganization(for: Self.provider)
    }

    func selectOrganization(_ id: String) {
        selectionStore.setSelectedOrganization(id, for: Self.provider)
    }

    func resetOrganizations() {
        selectionStore.setSelectedOrganization(nil, for: Self.provider)
        organizations = []
    }

    func fetchReport(credentials: [String: String], today: Date) async throws -> ProviderReport {
        guard let sessionKey = credentials["session-key"] else {
            throw FetchError.unauthorized
        }

        // Known even when the fetch fails for want of a choice: that is when the picker needs them.
        defer {
            organizations = service.organizations(sessionKey: sessionKey).map {
                AccountOrganization(id: $0.uuid, name: $0.name, detail: $0.detail)
            }
        }

        let snapshot = try await service.fetchSubscription(sessionKey: sessionKey, organizationID: selectedOrganizationID)

        return AnthropicReportMapper.subscription(snapshot, now: today)
    }

    func startSession(credentials: [String: String]) async throws {
        guard let sessionKey = credentials["session-key"] else {
            throw FetchError.unauthorized
        }

        try await service.startSession(
            sessionKey: sessionKey,
            organizationID: selectedOrganizationID,
            model: models.model(for: Self.provider)
        )
    }
}

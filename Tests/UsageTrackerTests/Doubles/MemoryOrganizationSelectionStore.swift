import Foundation
@testable import UsageTracker

final class MemoryOrganizationSelectionStore: OrganizationSelectionStoring {
    var selections: [Provider: String] = [:]

    func selectedOrganization(for provider: Provider) -> String? {
        selections[provider]
    }

    func setSelectedOrganization(_ id: String?, for provider: Provider) {
        selections[provider] = id
    }
}

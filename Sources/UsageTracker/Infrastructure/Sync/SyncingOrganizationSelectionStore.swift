import Foundation

/// Tells sync when the organization choice changes, so the other Macs fetch
/// for the same organization.
final class SyncingOrganizationSelectionStore: OrganizationSelectionStoring {
    private let inner: OrganizationSelectionStoring
    /// Called on the main actor, where the organization-scoped services run.
    var onChange: (@MainActor (Provider, String?) -> Void)?

    init(inner: OrganizationSelectionStoring) {
        self.inner = inner
    }

    func selectedOrganization(for provider: Provider) -> String? {
        inner.selectedOrganization(for: provider)
    }

    func setSelectedOrganization(_ id: String?, for provider: Provider) {
        guard inner.selectedOrganization(for: provider) != id else {
            return
        }

        inner.setSelectedOrganization(id, for: provider)
        if let onChange {
            MainActor.assumeIsolated { onChange(provider, id) }
        }
    }
}

import Foundation
import Testing
@testable import UsageTracker

@Suite struct OrganizationSelectionStoreTests {
    @Test func roundTripsPerProviderAndClearsWithNil() {
        withIsolatedDefaults { defaults in
            let store = UserDefaultsOrganizationSelectionStore(defaults: defaults)
            #expect(store.selectedOrganization(for: .anthropic) == nil)

            store.setSelectedOrganization("org-b", for: .anthropic)
            #expect(UserDefaultsOrganizationSelectionStore(defaults: defaults).selectedOrganization(for: .anthropic) == "org-b")
            #expect(store.selectedOrganization(for: .cursor) == nil)

            store.setSelectedOrganization(nil, for: .anthropic)
            #expect(store.selectedOrganization(for: .anthropic) == nil)
            #expect(defaults.object(forKey: UserDefaultsOrganizationSelectionStore.key(for: .anthropic)) == nil)
        }
    }

    @Test func blankSelectionReadsAsNone() {
        withIsolatedDefaults { defaults in
            defaults.set("  ", forKey: UserDefaultsOrganizationSelectionStore.key(for: .anthropic))

            #expect(UserDefaultsOrganizationSelectionStore(defaults: defaults).selectedOrganization(for: .anthropic) == nil)
        }
    }
}

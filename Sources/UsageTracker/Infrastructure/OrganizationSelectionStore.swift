import Foundation

/// The account organization the user chose for each provider whose
/// credential can see several.
protocol OrganizationSelectionStoring: AnyObject {
    func selectedOrganization(for provider: Provider) -> String?
    /// Nil forgets the choice.
    func setSelectedOrganization(_ id: String?, for provider: Provider)
}

final class UserDefaultsOrganizationSelectionStore: OrganizationSelectionStoring {
    static func key(for provider: Provider) -> String {
        "provider.\(provider.rawValue).organization"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func selectedOrganization(for provider: Provider) -> String? {
        defaults.string(forKey: Self.key(for: provider))
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }

    func setSelectedOrganization(_ id: String?, for provider: Provider) {
        guard let id else {
            defaults.removeObject(forKey: Self.key(for: provider))
            return
        }

        defaults.set(id, forKey: Self.key(for: provider))
    }
}

import Foundation

protocol ProviderSettingsStoring: AnyObject {
    func settings(for provider: Provider) -> ProviderSettings
    func setSettings(_ settings: ProviderSettings, for provider: Provider)
}

/// One JSON record per provider in user defaults.
final class UserDefaultsProviderSettingsStore: ProviderSettingsStoring {
    static func key(for provider: Provider) -> String {
        "provider.\(provider.rawValue).settings"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func settings(for provider: Provider) -> ProviderSettings {
        var settings = ProviderSettings.default
        var unresolved = ProviderSettings.UnresolvedMenuBarHalves(subscription: true, api: true)

        if let data = defaults.data(forKey: Self.key(for: provider)),
           let decoded = try? JSONDecoder().decode(ProviderSettings.self, from: data) {
            settings = decoded
            unresolved = decoded.unresolvedMenuBarHalves
        }

        // A half the record has no value for takes the old global switch, else stays on.
        if unresolved.subscription {
            settings.showsSubscriptionInMenuBar = legacyGlobalSwitch(UserDefaultsMenuBarAppearanceStore.showPlanUsageKey)
        }

        if unresolved.api {
            settings.showsAPIInMenuBar = legacyGlobalSwitch(UserDefaultsMenuBarAppearanceStore.showAPISpendKey)
        }

        return settings
    }

    private func legacyGlobalSwitch(_ key: String) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    func setSettings(_ settings: ProviderSettings, for provider: Provider) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }

        defaults.set(data, forKey: Self.key(for: provider))
    }
}

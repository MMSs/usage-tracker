import Foundation

protocol ProviderSettingsStoring: AnyObject {
    func settings(for provider: Provider) -> ProviderSettings
    /// The settings with the halves only the old menu bar switches hid.
    func loadSettings(for provider: Provider) -> ProviderSettings.Loaded
    func setSettings(_ settings: ProviderSettings, for provider: Provider)
}

extension ProviderSettingsStoring {
    /// A store with no old records has nothing to re-check.
    func loadSettings(for provider: Provider) -> ProviderSettings.Loaded {
        ProviderSettings.Loaded(settings: settings(for: provider))
    }
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
        loadSettings(for: provider).settings
    }

    func loadSettings(for provider: Provider) -> ProviderSettings.Loaded {
        let capabilities = ProviderRegistry.descriptor(for: provider).capabilities
        let decoder = JSONDecoder()
        decoder.userInfo[ProviderSettings.legacyHalvesKey] = ProviderSettings.LegacyHalves(
            globalSubscription: legacyGlobalSwitch(UserDefaultsMenuBarAppearanceStore.showPlanUsageKey),
            globalAPI: legacyGlobalSwitch(UserDefaultsMenuBarAppearanceStore.showAPISpendKey),
            hasSubscription: capabilities.hasSubscription,
            hasAPI: capabilities.hasAPISpend
        )

        // No record migrates like an empty one, so it picks up the old global switches too.
        let empty = Data("{}".utf8)
        let data = defaults.data(forKey: Self.key(for: provider)) ?? empty
        return (try? decoder.decode(ProviderSettings.Loaded.self, from: data))
            ?? (try? decoder.decode(ProviderSettings.Loaded.self, from: empty))
            ?? ProviderSettings.Loaded(settings: .default)
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

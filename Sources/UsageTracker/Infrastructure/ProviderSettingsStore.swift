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
        guard let data = defaults.data(forKey: Self.key(for: provider)),
              let settings = try? JSONDecoder().decode(ProviderSettings.self, from: data)
        else {
            return .default
        }

        return settings
    }

    func setSettings(_ settings: ProviderSettings, for provider: Provider) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }

        defaults.set(data, forKey: Self.key(for: provider))
    }
}

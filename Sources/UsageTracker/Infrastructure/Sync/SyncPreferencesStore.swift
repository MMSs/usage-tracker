import Foundation

/// This Mac's own sync state, never synced: what it shares, and the id that
/// tells its records from the other Macs'.
protocol SyncPreferencesStoring: AnyObject {
    var choices: SyncChoices { get set }
    var deviceID: String { get }
}

final class UserDefaultsSyncPreferencesStore: SyncPreferencesStoring {
    static let settingsKey = "sync.settings"
    static let providersKey = "sync.providers"
    /// The single choice from before providers were shared one by one; read until the first new choice replaces it.
    static let legacyModeKey = "sync.mode"
    static let deviceIDKey = "sync.deviceID"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var choices: SyncChoices {
        get {
            guard defaults.object(forKey: Self.settingsKey) != nil || defaults.object(forKey: Self.providersKey) != nil else {
                return defaults.string(forKey: Self.legacyModeKey).flatMap(SyncChoices.init(legacyMode:)) ?? .nothing
            }

            let providers = (defaults.stringArray(forKey: Self.providersKey) ?? []).compactMap(Provider.init(rawValue:))
            return SyncChoices(sharesSettings: defaults.bool(forKey: Self.settingsKey), sharedProviders: Set(providers))
        }
        set {
            defaults.set(newValue.sharesSettings, forKey: Self.settingsKey)
            defaults.set(newValue.sharedProviders.map(\.rawValue).sorted(), forKey: Self.providersKey)
            defaults.removeObject(forKey: Self.legacyModeKey)
        }
    }

    /// Made on first use and kept for this install.
    var deviceID: String {
        if let id = defaults.string(forKey: Self.deviceIDKey) {
            return id
        }

        let id = UUID().uuidString
        defaults.set(id, forKey: Self.deviceIDKey)
        return id
    }
}

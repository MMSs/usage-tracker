import Foundation

/// The user's Open at login choice. No value means they have not been asked
/// yet, which is a fresh install (or a new bundle identifier).
protocol LoginItemPreferenceStoring: AnyObject {
    func preference() -> Bool?
    func setPreference(_ isOn: Bool)
}

final class UserDefaultsLoginItemPreferenceStore: LoginItemPreferenceStoring {
    static let key = "openAtLogin"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func preference() -> Bool? {
        defaults.object(forKey: Self.key) as? Bool
    }

    func setPreference(_ isOn: Bool) {
        defaults.set(isOn, forKey: Self.key)
    }
}

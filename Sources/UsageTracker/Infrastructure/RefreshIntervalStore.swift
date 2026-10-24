import Foundation

protocol RefreshIntervalStoring {
    func interval() -> RefreshInterval
    func setInterval(_ interval: RefreshInterval)
}

final class UserDefaultsRefreshIntervalStore: RefreshIntervalStoring {
    private static let key = "refreshInterval"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func interval() -> RefreshInterval {
        guard let rawValue = defaults.string(forKey: Self.key),
              let interval = RefreshInterval(rawValue: rawValue)
        else {
            return .default
        }

        return interval
    }

    func setInterval(_ interval: RefreshInterval) {
        defaults.set(interval.rawValue, forKey: Self.key)
    }
}

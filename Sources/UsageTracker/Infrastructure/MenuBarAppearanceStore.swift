import Foundation

protocol MenuBarAppearanceStoring: AnyObject {
    func appearance() -> MenuBarAppearance
    func setAppearance(_ appearance: MenuBarAppearance)
}

final class UserDefaultsMenuBarAppearanceStore: MenuBarAppearanceStoring {
    static let showTextKey = "menuBarShowText"
    static let countdownKey = "menuBarCountdown"
    static let showGraphKey = "menuBarShowGraph"
    static let graphStyleKey = "menuBarGraphStyle"
    static let coloredKey = "menuBarColored"
    /// No longer read or written here; `UserDefaultsProviderSettingsStore` reads them to migrate.
    static let showPlanUsageKey = "menuBarShowPlanUsage"
    static let showAPISpendKey = "menuBarShowAPISpend"
    static let limitsKey = "menuBarLimits"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func appearance() -> MenuBarAppearance {
        let fallback = MenuBarAppearance.default

        return MenuBarAppearance(
            showText: bool(Self.showTextKey) ?? fallback.showText,
            countdown: bool(Self.countdownKey) ?? fallback.countdown,
            showGraph: bool(Self.showGraphKey) ?? fallback.showGraph,
            graphStyle: defaults.string(forKey: Self.graphStyleKey).flatMap(MenuBarGraphStyle.init(rawValue:))
                ?? fallback.graphStyle,
            colored: bool(Self.coloredKey) ?? fallback.colored,
            limits: defaults.string(forKey: Self.limitsKey).flatMap(MenuBarLimits.init(rawValue:))
                ?? fallback.limits
        )
    }

    func setAppearance(_ appearance: MenuBarAppearance) {
        defaults.set(appearance.showText, forKey: Self.showTextKey)
        defaults.set(appearance.countdown, forKey: Self.countdownKey)
        defaults.set(appearance.showGraph, forKey: Self.showGraphKey)
        defaults.set(appearance.graphStyle.rawValue, forKey: Self.graphStyleKey)
        defaults.set(appearance.colored, forKey: Self.coloredKey)
        defaults.set(appearance.limits.rawValue, forKey: Self.limitsKey)
    }

    private func bool(_ key: String) -> Bool? {
        defaults.object(forKey: key) as? Bool
    }
}

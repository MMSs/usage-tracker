import Foundation

/// What a user can set per provider. Appearance falls back to the global
/// defaults unless overridden here.
struct ProviderSettings: Equatable, Codable, Sendable {
    var isEnabled = true
    var refreshInterval = RefreshInterval.default
    var appearanceOverride: MenuBarAppearance?

    static let `default` = ProviderSettings()

    init(isEnabled: Bool = true, refreshInterval: RefreshInterval = .default, appearanceOverride: MenuBarAppearance? = nil) {
        self.isEnabled = isEnabled
        self.refreshInterval = refreshInterval
        self.appearanceOverride = appearanceOverride
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, refreshInterval, appearanceOverride
    }

    /// Missing or unknown values fall back to the defaults so older records still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        refreshInterval = try container.decodeIfPresent(String.self, forKey: .refreshInterval)
            .flatMap(RefreshInterval.init(rawValue:)) ?? .default
        appearanceOverride = try? container.decodeIfPresent(MenuBarAppearance.self, forKey: .appearanceOverride)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(refreshInterval.rawValue, forKey: .refreshInterval)
        try container.encodeIfPresent(appearanceOverride, forKey: .appearanceOverride)
    }
}

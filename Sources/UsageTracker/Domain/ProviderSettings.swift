import Foundation

/// What a user can set per provider. Appearance falls back to the global
/// defaults unless overridden here. Each half (subscription, API usage) can
/// be switched off on its own; it then has no meters and is never fetched.
struct ProviderSettings: Equatable, Codable, Sendable {
    var isEnabled = true
    var subscriptionRefreshInterval = RefreshInterval.default
    var apiRefreshInterval = RefreshInterval.default
    var appearanceOverride: MenuBarAppearance?
    var isSubscriptionEnabled = true
    var isAPIEnabled = true
    var alertsEnabled = true
    /// Start the provider's session from a scheduled refresh once the previous one ended.
    var autoStartSessions = false

    static let `default` = ProviderSettings()

    init(
        isEnabled: Bool = true,
        subscriptionRefreshInterval: RefreshInterval = .default,
        apiRefreshInterval: RefreshInterval = .default,
        appearanceOverride: MenuBarAppearance? = nil,
        isSubscriptionEnabled: Bool = true,
        isAPIEnabled: Bool = true,
        alertsEnabled: Bool = true,
        autoStartSessions: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.subscriptionRefreshInterval = subscriptionRefreshInterval
        self.apiRefreshInterval = apiRefreshInterval
        self.appearanceOverride = appearanceOverride
        self.isSubscriptionEnabled = isSubscriptionEnabled
        self.isAPIEnabled = isAPIEnabled
        self.alertsEnabled = alertsEnabled
        self.autoStartSessions = autoStartSessions
    }

    func isEnabled(_ half: Half) -> Bool {
        switch half {
        case .subscription: isSubscriptionEnabled
        case .api: isAPIEnabled
        }
    }

    mutating func setEnabled(_ enabled: Bool, for half: Half) {
        switch half {
        case .subscription: isSubscriptionEnabled = enabled
        case .api: isAPIEnabled = enabled
        }
    }

    func refreshInterval(for half: Half) -> RefreshInterval {
        switch half {
        case .subscription: subscriptionRefreshInterval
        case .api: apiRefreshInterval
        }
    }

    mutating func setRefreshInterval(_ interval: RefreshInterval, for half: Half) {
        switch half {
        case .subscription: subscriptionRefreshInterval = interval
        case .api: apiRefreshInterval = interval
        }
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, subscriptionRefreshInterval, apiRefreshInterval, appearanceOverride, isSubscriptionEnabled, isAPIEnabled, alertsEnabled, autoStartSessions
        /// The single interval records had before the halves got their own; read, never written.
        case refreshInterval
    }

    /// Missing or unknown values fall back to the defaults so older records still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        let sharedInterval = try container.decodeIfPresent(String.self, forKey: .refreshInterval)
            .flatMap(RefreshInterval.init(rawValue:)) ?? .default
        subscriptionRefreshInterval = try container.decodeIfPresent(String.self, forKey: .subscriptionRefreshInterval)
            .flatMap(RefreshInterval.init(rawValue:)) ?? sharedInterval
        apiRefreshInterval = try container.decodeIfPresent(String.self, forKey: .apiRefreshInterval)
            .flatMap(RefreshInterval.init(rawValue:)) ?? sharedInterval
        appearanceOverride = try? container.decodeIfPresent(MenuBarAppearance.self, forKey: .appearanceOverride)
        isSubscriptionEnabled = try container.decodeIfPresent(Bool.self, forKey: .isSubscriptionEnabled) ?? true
        isAPIEnabled = try container.decodeIfPresent(Bool.self, forKey: .isAPIEnabled) ?? true
        alertsEnabled = try container.decodeIfPresent(Bool.self, forKey: .alertsEnabled) ?? true
        autoStartSessions = try container.decodeIfPresent(Bool.self, forKey: .autoStartSessions) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(subscriptionRefreshInterval.rawValue, forKey: .subscriptionRefreshInterval)
        try container.encode(apiRefreshInterval.rawValue, forKey: .apiRefreshInterval)
        try container.encodeIfPresent(appearanceOverride, forKey: .appearanceOverride)
        try container.encode(isSubscriptionEnabled, forKey: .isSubscriptionEnabled)
        try container.encode(isAPIEnabled, forKey: .isAPIEnabled)
        try container.encode(alertsEnabled, forKey: .alertsEnabled)
        try container.encode(autoStartSessions, forKey: .autoStartSessions)
    }
}

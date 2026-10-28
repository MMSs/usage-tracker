import Foundation

/// A record's body with the Mac that wrote it and when, so a Mac can tell
/// its own writes coming back from another Mac's.
struct SyncEnvelope<Body: Codable>: Codable {
    let device: String
    let stamp: Date
    let body: Body
}

/// A setting the Macs share, one record each; the last save wins.
enum SyncedSetting: Equatable, Sendable {
    case provider(Provider, ProviderSettings)
    case appearance(MenuBarAppearance)
    case alerts(AlertSwitches)
    case budget(Provider, Decimal?)

    var recordName: String {
        switch self {
        case let .provider(provider, _): "settings.provider.\(provider.rawValue)"
        case .appearance: "settings.appearance"
        case .alerts: "settings.alerts"
        case let .budget(provider, _): "settings.budget.\(provider.rawValue)"
        }
    }
}

/// The alerts master switch and the kinds switched on.
struct AlertSwitches: Codable, Equatable, Sendable {
    var enabled: Bool
    var kinds: [String]
}

/// Which Mac is fetching a half now, and until when at the latest.
struct FetchLease: Codable, Equatable, Sendable {
    let device: String
    let expiresAt: Date
}

/// The last session start any Mac attempted for a provider.
struct SessionStartClaim: Codable, Equatable, Sendable {
    let device: String
    let attemptedAt: Date
}

/// A provider's usage history, each window's samples in `UsageSampleCoding`.
struct SharedHistory: Codable, Equatable, Sendable {
    var windows: [String: Data]

    init(_ samples: [String: [UsageSample]]) {
        windows = samples.mapValues(UsageSampleCoding.encode)
    }

    var samples: [String: [UsageSample]] {
        windows.mapValues(UsageSampleCoding.decode)
    }
}

/// The organization chosen for a provider; nil when none is.
struct SharedOrganization: Codable, Equatable, Sendable {
    let id: String?
}

enum SyncRecordName {
    static func usage(_ target: RefreshTarget) -> String {
        "usage.\(target.provider.rawValue).\(target.half.rawValue)"
    }

    static func lease(_ target: RefreshTarget) -> String {
        "lease.\(target.provider.rawValue).\(target.half.rawValue)"
    }

    static func session(_ provider: Provider) -> String {
        "session.\(provider.rawValue)"
    }

    static func history(_ provider: Provider) -> String {
        "history.\(provider.rawValue)"
    }

    static func organization(_ provider: Provider) -> String {
        "org.\(provider.rawValue)"
    }
}

/// JSON for record payloads. Dates keep their full precision: which Mac's
/// state is newer is decided by comparing them.
enum SyncCoding {
    static func encode(_ value: some Encodable) throws -> Data {
        try JSONEncoder().encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}

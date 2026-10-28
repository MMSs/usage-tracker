import Foundation

/// What this Mac shares with the user's other Macs through iCloud.
enum SyncMode: String, CaseIterable, Identifiable, Sendable {
    case off
    /// Settings only: each Mac keeps its own credentials and fetches for itself.
    case settingsOnly
    /// Settings, credentials and usage: the Macs take turns fetching.
    case everything

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .settingsOnly: "Settings only"
        case .everything: "Everything"
        }
    }

    var sharesSettings: Bool { self != .off }
    var sharesCredentials: Bool { self == .everything }
    /// Reports, history, fetch turns and session starts. Only with shared
    /// credentials: with its own, another Mac's figures could be another account's.
    var sharesUsage: Bool { self == .everything }
}

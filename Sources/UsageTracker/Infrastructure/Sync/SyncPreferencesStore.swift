import Foundation

/// This Mac's own sync state, never synced: the mode, and the id that tells
/// its records from the other Macs'.
protocol SyncPreferencesStoring: AnyObject {
    var mode: SyncMode { get set }
    var deviceID: String { get }
}

final class UserDefaultsSyncPreferencesStore: SyncPreferencesStoring {
    static let modeKey = "sync.mode"
    static let deviceIDKey = "sync.deviceID"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var mode: SyncMode {
        get { defaults.string(forKey: Self.modeKey).flatMap(SyncMode.init(rawValue:)) ?? .off }
        set { defaults.set(newValue.rawValue, forKey: Self.modeKey) }
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

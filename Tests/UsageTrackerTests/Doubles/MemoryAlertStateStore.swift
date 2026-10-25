import Foundation
@testable import UsageTracker

final class MemoryAlertStateStore: AlertStateStoring {
    var isEnabled = true
    private var kinds: [AlertKind: Bool] = [:]
    private(set) var keys: [String] = []
    /// Calls that change `keys`, or would have.
    private(set) var writes = 0

    func isEnabled(_ kind: AlertKind) -> Bool {
        kinds[kind] ?? kind.defaultEnabled
    }

    func setEnabled(_ enabled: Bool, for kind: AlertKind) {
        kinds[kind] = enabled
    }

    func hasDelivered(_ key: String) -> Bool {
        keys.contains(key)
    }

    func markDelivered(_ key: String) {
        writes += 1
        keys.append(key)
    }

    func clearDelivered(_ key: String) {
        writes += 1
        keys.removeAll { $0 == key }
    }
}

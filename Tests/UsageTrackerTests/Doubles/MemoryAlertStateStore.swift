import Foundation
@testable import UsageTracker

final class MemoryAlertStateStore: AlertStateStoring {
    var isEnabled = true
    private(set) var keys: [String] = []

    func hasDelivered(_ key: String) -> Bool {
        keys.contains(key)
    }

    func markDelivered(_ key: String) {
        keys.append(key)
    }

    func clearDelivered(_ key: String) {
        keys.removeAll { $0 == key }
    }
}

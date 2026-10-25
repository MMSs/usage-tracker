import Foundation
import Testing

@testable import UsageTracker

struct AlertStateStoreTests {
    @Test func enabledDefaultsOnAndPersists() {
        withIsolatedDefaults { defaults in
            let store = UserDefaultsAlertStateStore(defaults: defaults)
            #expect(store.isEnabled)

            store.isEnabled = false

            #expect(!UserDefaultsAlertStateStore(defaults: defaults).isEnabled)
        }
    }

    @Test func deliveredKeysOutliveTheMonitor() {
        withIsolatedDefaults { defaults in
            UserDefaultsAlertStateStore(defaults: defaults).markDelivered("a.80")
            let reopened = UserDefaultsAlertStateStore(defaults: defaults)

            #expect(reopened.hasDelivered("a.80"))

            reopened.clearDelivered("a.80")

            #expect(!UserDefaultsAlertStateStore(defaults: defaults).hasDelivered("a.80"))
        }
    }

    @Test func theCapKeepsTheNewest() {
        withIsolatedDefaults { defaults in
            let store = UserDefaultsAlertStateStore(defaults: defaults)

            for index in 0..<205 {
                store.markDelivered("key\(index)")
            }

            #expect(!store.hasDelivered("key4"))
            #expect(store.hasDelivered("key5"))
            #expect(store.hasDelivered("key204"))
        }
    }
}

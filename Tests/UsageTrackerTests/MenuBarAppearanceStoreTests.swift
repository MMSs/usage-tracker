import Foundation
import Testing
@testable import UsageTracker

@Suite struct MenuBarAppearanceStoreTests {
    @Test func anEmptyStoreReadsBackTheDefaults() {
        withDefaults { defaults in
            #expect(UserDefaultsMenuBarAppearanceStore(defaults: defaults).appearance() == .default)
        }
    }

    @Test func aStoredAppearanceSurvivesTheRoundTrip() {
        withDefaults { defaults in
            let stored = MenuBarAppearance(showText: false, countdown: true, showGraph: true, graphStyle: .bars, colored: true)

            UserDefaultsMenuBarAppearanceStore(defaults: defaults).setAppearance(stored)

            #expect(UserDefaultsMenuBarAppearanceStore(defaults: defaults).appearance() == stored)
        }
    }

    @Test func anUnknownGraphStyleFallsBackToRings() {
        withDefaults { defaults in
            defaults.set("sparkline", forKey: UserDefaultsMenuBarAppearanceStore.graphStyleKey)

            #expect(UserDefaultsMenuBarAppearanceStore(defaults: defaults).appearance().graphStyle == .rings)
        }
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        body(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }
}

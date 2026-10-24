import Foundation
import Testing
@testable import UsageTracker

@Suite struct MenuBarAppearanceStoreTests {
    @Test func anEmptyStoreReadsBackTheDefaults() {
        withIsolatedDefaults { defaults in
            #expect(UserDefaultsMenuBarAppearanceStore(defaults: defaults).appearance() == .default)
        }
    }

    @Test func aStoredAppearanceSurvivesTheRoundTrip() {
        withIsolatedDefaults { defaults in
            let stored = MenuBarAppearance(showText: false, countdown: true, showGraph: true, graphStyle: .bars, colored: true)

            UserDefaultsMenuBarAppearanceStore(defaults: defaults).setAppearance(stored)

            #expect(UserDefaultsMenuBarAppearanceStore(defaults: defaults).appearance() == stored)
        }
    }

    @Test func anUnknownGraphStyleFallsBackToRings() {
        withIsolatedDefaults { defaults in
            defaults.set("sparkline", forKey: UserDefaultsMenuBarAppearanceStore.graphStyleKey)

            #expect(UserDefaultsMenuBarAppearanceStore(defaults: defaults).appearance().graphStyle == .rings)
        }
    }
}

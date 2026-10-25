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
            let stored = MenuBarAppearance(showText: false, countdown: true, showGraph: true, graphStyle: .bars, colored: true,
                                        showPlanUsage: false, showAPISpend: true, limits: .long)

            UserDefaultsMenuBarAppearanceStore(defaults: defaults).setAppearance(stored)

            #expect(UserDefaultsMenuBarAppearanceStore(defaults: defaults).appearance() == stored)
        }
    }

    @Test func anUnknownGraphStyleFallsBackToRings() {
        withIsolatedDefaults { defaults in
            defaults.set("hexagons", forKey: UserDefaultsMenuBarAppearanceStore.graphStyleKey)

            #expect(UserDefaultsMenuBarAppearanceStore(defaults: defaults).appearance().graphStyle == .rings)
        }
    }

    @Test func anUnknownLimitsFallsBackToBoth() {
        withIsolatedDefaults { defaults in
            defaults.set("middle", forKey: UserDefaultsMenuBarAppearanceStore.limitsKey)

            #expect(UserDefaultsMenuBarAppearanceStore(defaults: defaults).appearance().limits == .both)
        }
    }
}

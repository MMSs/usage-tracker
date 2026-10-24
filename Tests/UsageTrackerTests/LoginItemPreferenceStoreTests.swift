import Testing
@testable import UsageTracker

@Suite struct LoginItemPreferenceStoreTests {
    @Test func anEmptyStoreHasNoPreference() {
        withIsolatedDefaults { defaults in
            #expect(UserDefaultsLoginItemPreferenceStore(defaults: defaults).preference() == nil)
        }
    }

    @Test func aStoredPreferenceSurvivesTheRoundTrip() {
        withIsolatedDefaults { defaults in
            UserDefaultsLoginItemPreferenceStore(defaults: defaults).setPreference(false)
            #expect(UserDefaultsLoginItemPreferenceStore(defaults: defaults).preference() == false)

            UserDefaultsLoginItemPreferenceStore(defaults: defaults).setPreference(true)
            #expect(UserDefaultsLoginItemPreferenceStore(defaults: defaults).preference() == true)
        }
    }
}

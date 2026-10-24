import Foundation
import Testing
@testable import UsageTracker

@Suite struct ProviderSettingsStoreTests {
    @Test func anEmptyStoreReadsBackTheDefaults() {
        withIsolatedDefaults { defaults in
            #expect(UserDefaultsProviderSettingsStore(defaults: defaults).settings(for: .cursor) == .default)
        }
    }

    @Test func settingsSurviveTheRoundTripPerProvider() {
        withIsolatedDefaults { defaults in
            let store = UserDefaultsProviderSettingsStore(defaults: defaults)
            let override = MenuBarAppearance(showText: false, countdown: true, showGraph: true, graphStyle: .bars, colored: true)
            let cursor = ProviderSettings(isEnabled: false, refreshInterval: .oneHour, appearanceOverride: override)

            store.setSettings(cursor, for: .cursor)

            #expect(UserDefaultsProviderSettingsStore(defaults: defaults).settings(for: .cursor) == cursor)
            #expect(UserDefaultsProviderSettingsStore(defaults: defaults).settings(for: .anthropic) == .default)
        }
    }

    @Test func missingAndUnknownValuesFallBackToDefaults() {
        withIsolatedDefaults { defaults in
            defaults.set(Data(#"{"isEnabled":false,"refreshInterval":"thirtyDays","appearanceOverride":{"bogus":1}}"#.utf8),
                         forKey: UserDefaultsProviderSettingsStore.key(for: .openai))

            let settings = UserDefaultsProviderSettingsStore(defaults: defaults).settings(for: .openai)

            #expect(settings.isEnabled == false)
            #expect(settings.refreshInterval == .default)
            #expect(settings.appearanceOverride == nil)
        }
    }

    @Test func halfFlagsRoundTripAndDefaultToOn() {
        withIsolatedDefaults { defaults in
            let store = UserDefaultsProviderSettingsStore(defaults: defaults)
            var settings = ProviderSettings()
            settings.setEnabled(false, for: .api)

            store.setSettings(settings, for: .anthropic)

            let read = UserDefaultsProviderSettingsStore(defaults: defaults).settings(for: .anthropic)
            #expect(read.isSubscriptionEnabled && !read.isAPIEnabled)
            #expect(!read.isEnabled(.api))

            defaults.set(Data(#"{"isEnabled":true}"#.utf8), forKey: UserDefaultsProviderSettingsStore.key(for: .cursor))
            let old = UserDefaultsProviderSettingsStore(defaults: defaults).settings(for: .cursor)
            #expect(old.isSubscriptionEnabled && old.isAPIEnabled)
        }
    }

    @Test func corruptDataReadsBackTheDefaults() {
        withIsolatedDefaults { defaults in
            defaults.set(Data("nope".utf8), forKey: UserDefaultsProviderSettingsStore.key(for: .cursor))

            #expect(UserDefaultsProviderSettingsStore(defaults: defaults).settings(for: .cursor) == .default)
        }
    }
}

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
            let cursor = ProviderSettings(
                isEnabled: false, subscriptionRefreshInterval: .thirtySeconds, apiRefreshInterval: .tenMinutes,
                appearanceOverride: override
            )

            store.setSettings(cursor, for: .cursor)

            #expect(UserDefaultsProviderSettingsStore(defaults: defaults).settings(for: .cursor) == cursor)
            #expect(UserDefaultsProviderSettingsStore(defaults: defaults).settings(for: .anthropic) == .default)
        }
    }

    @Test func aSinglePlan5IntervalCarriesToBothHalves() {
        withIsolatedDefaults { defaults in
            defaults.set(Data(#"{"isEnabled":true,"refreshInterval":"thirtySeconds"}"#.utf8),
                         forKey: UserDefaultsProviderSettingsStore.key(for: .openai))

            let settings = UserDefaultsProviderSettingsStore(defaults: defaults).settings(for: .openai)

            #expect(settings.refreshInterval(for: .subscription) == .thirtySeconds)
            #expect(settings.refreshInterval(for: .api) == .thirtySeconds)
        }
    }

    @Test func eachHalfKeepsItsOwnInterval() throws {
        var settings = ProviderSettings()
        settings.setRefreshInterval(.thirtySeconds, for: .subscription)
        settings.setRefreshInterval(.tenMinutes, for: .api)

        let data = try JSONEncoder().encode(settings)
        let json = try #require(String(data: data, encoding: .utf8))
        let decoded = try JSONDecoder().decode(ProviderSettings.self, from: data)

        #expect(decoded.refreshInterval(for: .subscription) == .thirtySeconds)
        #expect(decoded.refreshInterval(for: .api) == .tenMinutes)
        #expect(!json.contains(#""refreshInterval""#))
    }

    @Test func alertsEnabledDefaultsOnForOlderRecords() {
        withIsolatedDefaults { defaults in
            defaults.set(Data(#"{"isEnabled":true}"#.utf8), forKey: UserDefaultsProviderSettingsStore.key(for: .openai))

            let store = UserDefaultsProviderSettingsStore(defaults: defaults)
            #expect(store.settings(for: .openai).alertsEnabled)

            var settings = ProviderSettings()
            settings.alertsEnabled = false
            store.setSettings(settings, for: .openai)

            #expect(!store.settings(for: .openai).alertsEnabled)
        }
    }

    @Test func autoStartDefaultsOffForOlderRecords() {
        withIsolatedDefaults { defaults in
            defaults.set(Data(#"{"isEnabled":true}"#.utf8), forKey: UserDefaultsProviderSettingsStore.key(for: .openai))

            let store = UserDefaultsProviderSettingsStore(defaults: defaults)
            #expect(!store.settings(for: .openai).autoStartSessions)

            var settings = ProviderSettings()
            settings.autoStartSessions = true
            store.setSettings(settings, for: .openai)

            #expect(store.settings(for: .openai).autoStartSessions)
        }
    }

    @Test func missingAndUnknownValuesFallBackToDefaults() {
        withIsolatedDefaults { defaults in
            defaults.set(Data(#"{"isEnabled":false,"refreshInterval":"thirtyDays","appearanceOverride":{"showText":"bogus"}}"#.utf8),
                         forKey: UserDefaultsProviderSettingsStore.key(for: .openai))

            let settings = UserDefaultsProviderSettingsStore(defaults: defaults).settings(for: .openai)

            #expect(settings.isEnabled == false)
            #expect(settings.subscriptionRefreshInterval == .default)
            #expect(settings.apiRefreshInterval == .default)
            #expect(settings.appearanceOverride == nil)
        }
    }

    @Test func anOverrideSavedBeforeTheVisibilityFieldsLoadsIntact() {
        withIsolatedDefaults { defaults in
            let json = #"{"isEnabled":true,"appearanceOverride":{"showText":false,"countdown":true,"showGraph":true,"graphStyle":"bars","colored":true}}"#
            defaults.set(Data(json.utf8), forKey: UserDefaultsProviderSettingsStore.key(for: .openai))

            let override = UserDefaultsProviderSettingsStore(defaults: defaults).settings(for: .openai).appearanceOverride

            #expect(override == MenuBarAppearance(showText: false, countdown: true, showGraph: true, graphStyle: .bars, colored: true))
        }
    }

    @Test func anOverrideWithARemovedStyleLoadsAsRings() throws {
        withIsolatedDefaults { defaults in
            let json = #"{"isEnabled":true,"appearanceOverride":{"showText":false,"countdown":true,"showGraph":true,"graphStyle":"sparkline","colored":true}}"#
            defaults.set(Data(json.utf8), forKey: UserDefaultsProviderSettingsStore.key(for: .openai))

            let override = UserDefaultsProviderSettingsStore(defaults: defaults).settings(for: .openai).appearanceOverride

            #expect(override?.graphStyle == .rings)
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

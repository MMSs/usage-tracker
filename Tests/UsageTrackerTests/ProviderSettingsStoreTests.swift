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

    @Test func aSwitchedOffCustomAppearanceSurvivesTheRoundTrip() throws {
        let custom = MenuBarAppearance(showText: false, countdown: true, showGraph: true, graphStyle: .bars, colored: true)
        var settings = ProviderSettings(appearanceOverride: custom)
        settings.setUsesCustomAppearance(false, defaults: .default)

        let data = try JSONEncoder().encode(settings)
        let json = try #require(String(data: data, encoding: .utf8))
        var decoded = try JSONDecoder().decode(ProviderSettings.self, from: data)

        #expect(decoded == settings)
        #expect(decoded.appearanceOverride == nil)
        // Older builds read an override from this key alone, so it is left out while switched off.
        #expect(!json.contains(#""appearanceOverride""#))
        decoded.setUsesCustomAppearance(true, defaults: .default)
        #expect(decoded.appearanceOverride == custom)
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

    @Test func anOverridesOldHalfSwitchCarriesOver() {
        withIsolatedDefaults { defaults in
            let json = #"{"isEnabled":true,"appearanceOverride":{"showText":true,"countdown":false,"showGraph":true,"graphStyle":"rings","colored":false,"showAPISpend":false}}"#
            defaults.set(Data(json.utf8), forKey: UserDefaultsProviderSettingsStore.key(for: .anthropic))

            let settings = UserDefaultsProviderSettingsStore(defaults: defaults).settings(for: .anthropic)

            #expect(settings.showsAPIInMenuBar == false)
            #expect(settings.showsSubscriptionInMenuBar == true)
        }
    }

    @Test func theOldGlobalHalfSwitchCarriesOver() {
        withIsolatedDefaults { defaults in
            defaults.set(false, forKey: UserDefaultsMenuBarAppearanceStore.showPlanUsageKey)
            defaults.set(Data(#"{"isEnabled":true}"#.utf8), forKey: UserDefaultsProviderSettingsStore.key(for: .anthropic))
            let store = UserDefaultsProviderSettingsStore(defaults: defaults)

            #expect(store.settings(for: .anthropic).showsSubscriptionInMenuBar == false)
            #expect(store.settings(for: .anthropic).showsAPIInMenuBar == true)
            // Cursor has no API half, so the switch never hid anything there.
            #expect(store.settings(for: .cursor).showsSubscriptionInMenuBar == true)
            // A provider with no record at all falls back the same way.
            #expect(store.settings(for: .openai).showsSubscriptionInMenuBar == false)
        }
    }

    @Test func aLegacyHiddenOnlyHalfStaysShown() {
        withIsolatedDefaults { defaults in
            defaults.set(false, forKey: UserDefaultsMenuBarAppearanceStore.showPlanUsageKey)

            #expect(UserDefaultsProviderSettingsStore(defaults: defaults).settings(for: .cursor).showsSubscriptionInMenuBar)
        }
    }

    @Test func aLegacyHiddenHalfWithItsOtherHalfOffStaysShown() {
        withIsolatedDefaults { defaults in
            defaults.set(false, forKey: UserDefaultsMenuBarAppearanceStore.showPlanUsageKey)
            defaults.set(Data(#"{"isAPIEnabled":false}"#.utf8), forKey: UserDefaultsProviderSettingsStore.key(for: .anthropic))
            let off = UserDefaultsProviderSettingsStore(defaults: defaults).settings(for: .anthropic)

            #expect(off.showsSubscriptionInMenuBar)

            defaults.set(Data(#"{"isAPIEnabled":true}"#.utf8), forKey: UserDefaultsProviderSettingsStore.key(for: .anthropic))
            #expect(!UserDefaultsProviderSettingsStore(defaults: defaults).settings(for: .anthropic).showsSubscriptionInMenuBar)
        }
    }

    @Test func aLoadReportsTheHalvesOnlyTheOldSwitchesHid() {
        withIsolatedDefaults { defaults in
            defaults.set(false, forKey: UserDefaultsMenuBarAppearanceStore.showPlanUsageKey)
            let store = UserDefaultsProviderSettingsStore(defaults: defaults)

            let legacy = store.loadSettings(for: .anthropic)
            #expect(!legacy.settings.showsSubscriptionInMenuBar)
            #expect(legacy.legacyHiddenHalves == [.subscription])

            // A record with the new keys is the user's own choice, never re-checked.
            var settings = ProviderSettings()
            settings.setShowsInMenuBar(false, for: .subscription)
            store.setSettings(settings, for: .anthropic)
            #expect(store.loadSettings(for: .anthropic).legacyHiddenHalves.isEmpty)
            #expect(store.loadSettings(for: .anthropic).settings == settings)
        }
    }

    @Test func anOverrideWithoutTheOldKeysShowsBoth() {
        withIsolatedDefaults { defaults in
            defaults.set(false, forKey: UserDefaultsMenuBarAppearanceStore.showPlanUsageKey)
            defaults.set(false, forKey: UserDefaultsMenuBarAppearanceStore.showAPISpendKey)
            let json = #"{"appearanceOverride":{"showText":true}}"#
            defaults.set(Data(json.utf8), forKey: UserDefaultsProviderSettingsStore.key(for: .anthropic))

            let settings = UserDefaultsProviderSettingsStore(defaults: defaults).settings(for: .anthropic)

            #expect(settings.showsSubscriptionInMenuBar && settings.showsAPIInMenuBar)
        }
    }

    @Test func anOverrideWinsOverTheGlobalSwitch() {
        withIsolatedDefaults { defaults in
            defaults.set(false, forKey: UserDefaultsMenuBarAppearanceStore.showAPISpendKey)
            let json = #"{"appearanceOverride":{"showAPISpend":true}}"#
            defaults.set(Data(json.utf8), forKey: UserDefaultsProviderSettingsStore.key(for: .anthropic))

            #expect(UserDefaultsProviderSettingsStore(defaults: defaults).settings(for: .anthropic).showsAPIInMenuBar)
        }
    }

    @Test func newKeysWinOverLegacyOnes() {
        withIsolatedDefaults { defaults in
            defaults.set(false, forKey: UserDefaultsMenuBarAppearanceStore.showPlanUsageKey)
            let json = #"{"showsSubscriptionInMenuBar":true,"showsAPIInMenuBar":true,"appearanceOverride":{"showAPISpend":false}}"#
            defaults.set(Data(json.utf8), forKey: UserDefaultsProviderSettingsStore.key(for: .anthropic))

            let settings = UserDefaultsProviderSettingsStore(defaults: defaults).settings(for: .anthropic)

            #expect(settings.showsSubscriptionInMenuBar)
            #expect(settings.showsAPIInMenuBar)
        }
    }

    @Test func newRecordsKeepTheirOwnValues() {
        withIsolatedDefaults { defaults in
            defaults.set(false, forKey: UserDefaultsMenuBarAppearanceStore.showPlanUsageKey)
            let store = UserDefaultsProviderSettingsStore(defaults: defaults)
            var settings = ProviderSettings()
            settings.setShowsInMenuBar(true, for: .subscription)
            settings.setShowsInMenuBar(false, for: .api)
            store.setSettings(settings, for: .anthropic)

            let loaded = store.settings(for: .anthropic)

            #expect(loaded == settings)
            #expect(loaded.showsInMenuBar(.subscription))
            #expect(!loaded.showsInMenuBar(.api))
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

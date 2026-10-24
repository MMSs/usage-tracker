import Foundation
import Testing
@testable import UsageTracker

@Suite struct ProviderSettingsStoreTests {
    @Test func anEmptyStoreReadsBackTheDefaults() {
        withDefaults { defaults in
            #expect(UserDefaultsProviderSettingsStore(defaults: defaults).settings(for: .cursor) == .default)
        }
    }

    @Test func settingsSurviveTheRoundTripPerProvider() {
        withDefaults { defaults in
            let store = UserDefaultsProviderSettingsStore(defaults: defaults)
            let override = MenuBarAppearance(showText: false, countdown: true, showGraph: true, graphStyle: .bars, colored: true)
            let cursor = ProviderSettings(isEnabled: false, refreshInterval: .oneHour, appearanceOverride: override)

            store.setSettings(cursor, for: .cursor)

            #expect(UserDefaultsProviderSettingsStore(defaults: defaults).settings(for: .cursor) == cursor)
            #expect(UserDefaultsProviderSettingsStore(defaults: defaults).settings(for: .anthropic) == .default)
        }
    }

    @Test func missingAndUnknownValuesFallBackToDefaults() {
        withDefaults { defaults in
            defaults.set(Data(#"{"isEnabled":false,"refreshInterval":"thirtyDays","appearanceOverride":{"bogus":1}}"#.utf8),
                         forKey: UserDefaultsProviderSettingsStore.key(for: .openai))

            let settings = UserDefaultsProviderSettingsStore(defaults: defaults).settings(for: .openai)

            #expect(settings.isEnabled == false)
            #expect(settings.refreshInterval == .default)
            #expect(settings.appearanceOverride == nil)
        }
    }

    @Test func corruptDataReadsBackTheDefaults() {
        withDefaults { defaults in
            defaults.set(Data("nope".utf8), forKey: UserDefaultsProviderSettingsStore.key(for: .cursor))

            #expect(UserDefaultsProviderSettingsStore(defaults: defaults).settings(for: .cursor) == .default)
        }
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        body(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }
}

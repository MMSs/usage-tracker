import Foundation
import Testing
@testable import UsageTracker

@Suite @MainActor struct AppModelTests {
    let credentials = MemoryCredentialStore()
    let cache = MemoryReportCache()
    let settingsStore = MemoryProviderSettingsStore()
    let sleeper = ControllableSleeper()
    let fetchers: [Provider: StubReportFetcher] = [
        .cursor: StubReportFetcher(result: .success(makeReport(1))),
        .anthropic: StubReportFetcher(result: .success(makeReport(2))),
        .openai: StubReportFetcher(result: .success(makeReport(3))),
    ]

    private func makeModel() -> AppModel {
        let providers = ProviderRegistry.all.map { descriptor in
            ProviderViewModel(
                descriptor: descriptor,
                subscriptionFetcher: fetchers[descriptor.id],
                apiFetcher: nil,
                credentialStore: credentials, cache: cache
            )
        }

        return AppModel(
            providers: providers,
            credentialStore: credentials,
            providerSettingsStore: settingsStore,
            appearanceStore: MemoryMenuBarAppearanceStore(),
            budgetStore: MemoryAPIBudgetStore(),
            sleepObserver: ControllableSleepObserver(),
            networkObserver: ControllableNetworkObserver(),
            sleep: { [sleeper] duration in await sleeper.sleep(duration) }
        )
    }

    private func makeModel(apiFetchers: [Provider: StubReportFetcher]) -> AppModel {
        let providers = ProviderRegistry.all.map { descriptor in
            ProviderViewModel(
                descriptor: descriptor,
                subscriptionFetcher: fetchers[descriptor.id],
                apiFetcher: apiFetchers[descriptor.id],
                credentialStore: credentials, cache: cache
            )
        }

        return AppModel(
            providers: providers,
            credentialStore: credentials,
            providerSettingsStore: settingsStore,
            appearanceStore: MemoryMenuBarAppearanceStore(),
            budgetStore: MemoryAPIBudgetStore(),
            sleepObserver: ControllableSleepObserver(),
            networkObserver: ControllableNetworkObserver(),
            sleep: { [sleeper] duration in await sleeper.sleep(duration) }
        )
    }

    private func configureAll() {
        for descriptor in ProviderRegistry.all {
            for field in descriptor.subscriptionFields {
                credentials.values[CredentialKey(provider: descriptor.id, fieldID: field.id)] = "secret"
            }
        }
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            await Task.yield()
        }
    }

    @Test func providersFollowRegistryOrder() {
        let model = makeModel()
        #expect(model.providers.map(\.id) == Provider.allCases)
        #expect(model.provider(.openai).id == .openai)
    }

    @Test func refreshAllFetchesEveryProviderOnce() async {
        configureAll()
        let model = makeModel()

        await model.refreshAll(manual: true)

        for provider in Provider.allCases {
            #expect(fetchers[provider]?.callCount == 1)
        }
    }

    @Test func providerSettingsPersistAndReachTheProvider() {
        let model = makeModel()
        let settings = ProviderSettings(isEnabled: false, refreshInterval: .oneHour, appearanceOverride: nil)

        model.setSettings(settings, for: .cursor)

        #expect(settingsStore.stored[.cursor] == settings)
        #expect(model.settings(for: .cursor) == settings)
        #expect(!model.provider(.cursor).isEnabled)
    }

    @Test func appearanceFallsBackToGlobalUnlessOverridden() {
        let model = makeModel()
        let global = MenuBarAppearance(showText: false, countdown: true, showGraph: true, graphStyle: .bars, colored: false)
        let override = MenuBarAppearance(showText: true, countdown: false, showGraph: false, graphStyle: .rings, colored: true)

        model.setGlobalAppearance(global)
        #expect(model.appearance(for: .cursor) == global)
        #expect(model.appearance(for: .anthropic) == global)

        model.setSettings(ProviderSettings(appearanceOverride: override), for: .cursor)
        #expect(model.appearance(for: .cursor) == override)
        #expect(model.appearance(for: .anthropic) == global)
    }

    @Test func disabledProvidersAreNeitherInsertedNorRefreshed() async {
        configureAll()
        let model = makeModel()

        model.setSettings(ProviderSettings(isEnabled: false), for: .anthropic)
        await model.refreshAll(manual: true)

        #expect(model.insertedProviders == [.cursor, .openai])
        #expect(fetchers[.anthropic]?.callCount == 0)
        #expect(fetchers[.cursor]?.callCount == 1)
    }

    @Test func enablingAProviderRefreshesItAtOnce() async {
        configureAll()
        let model = makeModel()
        model.setSettings(ProviderSettings(isEnabled: false), for: .cursor)

        model.setSettings(ProviderSettings(isEnabled: true), for: .cursor)
        await waitUntil { fetchers[.cursor]?.callCount == 1 }

        #expect(fetchers[.cursor]?.callCount == 1)

        model.setSettings(ProviderSettings(isEnabled: true, refreshInterval: .oneHour), for: .cursor)
        await settle()

        #expect(fetchers[.cursor]?.callCount == 1, "a change while already enabled does not refetch")
    }

    @Test func aDisabledHalfIsNeitherShownNorFetched() async {
        configureAll()
        let model = makeModel()

        model.setSettings(ProviderSettings(isSubscriptionEnabled: false), for: .cursor)
        await model.refreshAll(manual: true)

        #expect(model.provider(.cursor).snapshot(.subscription) == nil)
        #expect(!model.provider(.cursor).hasActiveHalf)
        #expect(model.insertedProviders == [.anthropic, .openai])
        #expect(fetchers[.cursor]?.callCount == 0)

        model.setSettings(ProviderSettings(isSubscriptionEnabled: true), for: .cursor)
        await waitUntil { fetchers[.cursor]?.callCount == 1 }

        #expect(model.provider(.cursor).snapshot(.subscription) != nil)
        #expect(model.insertedProviders == [.cursor, .anthropic, .openai])
    }

    @Test func disablingEveryConfiguredProviderLeavesTheMenuBarEmpty() {
        credentials.values[CredentialKey(provider: .cursor, fieldID: "session-token")] = "secret"
        let model = makeModel()

        model.setSettings(ProviderSettings(isEnabled: false), for: .cursor)

        #expect(model.insertedProviders == [])
    }

    @Test func startPerformsLaunchRefreshOnlyOnce() async {
        configureAll()
        let model = makeModel()

        model.start()
        await waitUntil { Provider.allCases.allSatisfy { fetchers[$0]?.callCount == 1 } }
        for provider in Provider.allCases {
            #expect(fetchers[provider]?.callCount == 1)
        }

        model.start()
        model.start()
        await settle()
        for provider in Provider.allCases {
            #expect(fetchers[provider]?.callCount == 1)
        }

        model.scheduler.stop()
        sleeper.resume()
    }

    @Test func insertedProvidersFallsBackToFirstProviderWhenNothingIsConfigured() {
        let model = makeModel()
        #expect(model.insertedProviders == [.cursor])
    }

    @Test func insertedProvidersContainsOnlyConfiguredProviders() {
        credentials.values[CredentialKey(provider: .anthropic, fieldID: "admin-key")] = "secret"
        let model = makeModel(apiFetchers: [.anthropic: StubReportFetcher(result: .success(makeReport(2)))])
        #expect(model.insertedProviders == [.anthropic])
    }
}

import Foundation
import Testing
@testable import UsageTracker

@Suite @MainActor struct AppModelTests {
    let credentials = MemoryCredentialStore()
    let cache = MemoryReportCache()
    let intervalStore = MemoryIntervalStore(.default)
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
            intervalStore: intervalStore,
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
            intervalStore: intervalStore,
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

    @Test func setIntervalPersists() {
        let model = makeModel()
        let other = RefreshInterval.allCases.first { $0 != .default }!

        model.setInterval(other)

        #expect(intervalStore.stored == other)
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

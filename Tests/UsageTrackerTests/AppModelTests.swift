import Combine
import Foundation
import Testing
@testable import UsageTracker

@Suite @MainActor struct AppModelTests {
    let credentials = MemoryCredentialStore()
    let cache = MemoryReportCache()
    let settingsStore = MemoryProviderSettingsStore()
    let budgets = MemoryAPIBudgetStore()
    let sleeper = ControllableSleeper()
    let notifier = RecordingNotifier()
    let alertStore = MemoryAlertStateStore()
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
            budgetStore: budgets,
            loginItem: .stub(),
            sleepObserver: ControllableSleepObserver(),
            networkObserver: ControllableNetworkObserver(),
            sleep: { [sleeper] duration in await sleeper.sleep(duration) },
            alertMonitor: AlertMonitor(notifier: notifier, store: alertStore)
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
            budgetStore: budgets,
            loginItem: .stub(),
            sleepObserver: ControllableSleepObserver(),
            networkObserver: ControllableNetworkObserver(),
            sleep: { [sleeper] duration in await sleeper.sleep(duration) },
            alertMonitor: AlertMonitor(notifier: notifier, store: alertStore)
        )
    }

    // MARK: Auto-start

    private final class Clock {
        var date = Date(timeIntervalSince1970: 1_000_000)
    }

    private func sessionReport(open: Bool, at date: Date) -> ProviderReport {
        ProviderReport(
            planName: nil,
            windows: [LimitWindow(
                id: "session", label: "Session", percentUsed: 10,
                resetsAt: open ? date.addingTimeInterval(3600) : nil, parentID: nil
            )],
            extras: [],
            spend: nil
        )
    }

    /// A model whose Anthropic subscription half is `starter`, with the clock `clock`.
    private func makeAutoStartModel(starter: StubSessionFetcher, clock: Clock, autoStart: Bool = true) -> AppModel {
        let providers = ProviderRegistry.all.map { descriptor in
            ProviderViewModel(
                descriptor: descriptor,
                subscriptionFetcher: descriptor.id == .anthropic ? starter : fetchers[descriptor.id],
                apiFetcher: nil,
                credentialStore: credentials, cache: cache
            )
        }
        let model = AppModel(
            providers: providers,
            credentialStore: credentials,
            providerSettingsStore: settingsStore,
            appearanceStore: MemoryMenuBarAppearanceStore(),
            budgetStore: budgets,
            loginItem: .stub(),
            sleepObserver: ControllableSleepObserver(),
            networkObserver: ControllableNetworkObserver(),
            sleep: { [sleeper] duration in await sleeper.sleep(duration) },
            now: { clock.date },
            alertMonitor: AlertMonitor(notifier: notifier, store: alertStore)
        )
        model.setSettings(ProviderSettings(autoStartSessions: autoStart), for: .anthropic)
        return model
    }

    @Test func autoStartFiresOnAScheduledRefreshWhenTheSessionIsClosed() async {
        configureAll()
        let clock = Clock()
        let starter = StubSessionFetcher(fetchResult: .success(sessionReport(open: false, at: clock.date)))
        let model = makeAutoStartModel(starter: starter, clock: clock)

        await model.refreshAll(manual: false)

        #expect(starter.startCount == 1)
    }

    @Test func autoStartFiresOnAPeriodicRefresh() async {
        configureAll()
        let clock = Clock()
        let starter = StubSessionFetcher(fetchResult: .success(sessionReport(open: false, at: clock.date)))
        let model = makeAutoStartModel(starter: starter, clock: clock)
        model.start()
        await sleeper.waitForSleepCount(1)
        // The initial refresh runs without sleeping; let it finish, then drive a periodic tick.
        await waitUntil { starter.startCount == 1 }
        clock.date.addTimeInterval(AppModel.autoStartInterval)
        sleeper.resume()
        await waitUntil { starter.startCount == 2 }

        #expect(starter.startCount == 2)
    }

    @Test func autoStartIsOffByDefault() async {
        configureAll()
        let clock = Clock()
        let starter = StubSessionFetcher(fetchResult: .success(sessionReport(open: false, at: clock.date)))
        let model = makeAutoStartModel(starter: starter, clock: clock, autoStart: false)

        await model.refreshAll(manual: false)

        #expect(starter.startCount == 0)
    }

    @Test func autoStartWaitsTenMinutesBetweenAttempts() async {
        configureAll()
        let clock = Clock()
        let starter = StubSessionFetcher(fetchResult: .success(sessionReport(open: false, at: clock.date)))
        // A failed attempt counts too.
        starter.startResults = [.failure(FetchError.transport)]
        let model = makeAutoStartModel(starter: starter, clock: clock)

        await model.refreshAll(manual: false)
        #expect(starter.startCount == 1)

        clock.date.addTimeInterval(9 * 60)
        await model.refreshAll(manual: false)
        #expect(starter.startCount == 1)

        clock.date.addTimeInterval(60)
        await model.refreshAll(manual: false)
        #expect(starter.startCount == 2)
    }

    @Test func autoStartSkipsHalvesThatAreNotReady() async {
        configureAll()
        let clock = Clock()
        let starter = StubSessionFetcher(fetchResult: .success(sessionReport(open: false, at: clock.date)))
        let model = makeAutoStartModel(starter: starter, clock: clock)
        await model.refreshAll(manual: true)
        #expect(starter.startCount == 0)

        starter.fetchResult = .failure(.transport)
        clock.date.addTimeInterval(3600)
        await model.refreshAll(manual: false)
        #expect(model.provider(.anthropic).subscription?.status == .error)
        #expect(starter.startCount == 0)

        starter.fetchResult = .failure(.unauthorized)
        clock.date.addTimeInterval(3600)
        await model.refreshAll(manual: false)
        #expect(model.provider(.anthropic).subscription?.status == .expired)
        #expect(starter.startCount == 0)
    }

    @Test func manualRefreshNeverAutoStarts() async {
        configureAll()
        let clock = Clock()
        let starter = StubSessionFetcher(fetchResult: .success(sessionReport(open: false, at: clock.date)))
        let model = makeAutoStartModel(starter: starter, clock: clock)

        await model.refreshAll(manual: true)

        #expect(starter.startCount == 0)
    }

    @Test func anOpenSessionIsNotStarted() async {
        configureAll()
        let clock = Clock()
        let starter = StubSessionFetcher(fetchResult: .success(sessionReport(open: true, at: clock.date)))
        let model = makeAutoStartModel(starter: starter, clock: clock)

        await model.refreshAll(manual: false)

        #expect(starter.startCount == 0)
    }

    private func hotReport(_ percent: Double = 90) -> ProviderReport {
        ProviderReport(
            planName: nil,
            windows: [LimitWindow(
                id: "session", label: "Session", percentUsed: percent,
                resetsAt: Date().addingTimeInterval(3600), parentID: nil
            )],
            extras: [],
            spend: nil
        )
    }

    private func useHotReport(for provider: Provider = .cursor) {
        for (id, fetcher) in fetchers {
            fetcher.result = .success(id == provider ? hotReport() : makeReport(1))
        }
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

    @Test func menuBarDisplayOrderIsOpenAIAnthropicCursor() {
        #expect(AppModel.menuBarDisplayOrder(Provider.allCases) == [.openai, .anthropic, .cursor])
    }

    @Test func theSetUpItemFallsBackToCursor() {
        #expect(makeModel().insertedProviders == [.cursor])
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
        #expect(model.showsSetUpItem)
        #expect(model.insertedProviders == [.cursor])
    }

    @Test func aConfiguredProviderReplacesTheSetUpItemEvenWhenSwitchedOff() {
        credentials.values[CredentialKey(provider: .cursor, fieldID: "session-token")] = "secret"
        let model = makeModel()

        #expect(!model.showsSetUpItem)

        model.setSettings(ProviderSettings(isEnabled: false), for: .cursor)
        #expect(!model.showsSetUpItem)
    }

    @Test func insertedProvidersContainsOnlyConfiguredProviders() {
        credentials.values[CredentialKey(provider: .anthropic, fieldID: "admin-key")] = "secret"
        let model = makeModel(apiFetchers: [.anthropic: StubReportFetcher(result: .success(makeReport(2)))])
        #expect(model.insertedProviders == [.anthropic])
    }

    @Test func settingABudgetPublishesAndClearingRemovesIt() {
        let model = makeModel()
        var changes = 0
        let subscription = model.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }

        #expect(model.budget(for: .anthropic) == nil)

        model.setBudget(50, for: .anthropic)

        #expect(model.budget(for: .anthropic) == 50)
        #expect(model.budget(for: .cursor) == nil)
        #expect(changes == 1)

        model.setBudget(nil, for: .anthropic)

        #expect(model.budget(for: .anthropic) == nil)
        #expect(changes == 2)
    }

    @Test func budgetsAlreadyStoredAreAvailableAtLaunch() {
        budgets.setBudget(20, for: .anthropic)

        let model = makeModel()

        #expect(model.budget(for: .anthropic) == 20)
    }

    @Test func aBudgetIsPersistedToTheStore() {
        let model = makeModel()

        model.setBudget(35, for: .anthropic)

        #expect(budgets.budget(for: .anthropic) == 35)
    }

    @Test(arguments: [Decimal(0), Decimal(-5)])
    func aBudgetTheStoreRejectsReadsBackAsNone(budget: Decimal) {
        withIsolatedDefaults { defaults in
            let model = AppModel(
                providers: ProviderRegistry.all.map { descriptor in
                    ProviderViewModel(
                        descriptor: descriptor,
                        subscriptionFetcher: nil,
                        apiFetcher: nil,
                        credentialStore: credentials, cache: cache
                    )
                },
                credentialStore: credentials,
                providerSettingsStore: settingsStore,
                appearanceStore: MemoryMenuBarAppearanceStore(),
                budgetStore: UserDefaultsAPIBudgetStore(defaults: defaults),
                loginItem: .stub(),
                sleepObserver: ControllableSleepObserver(),
                networkObserver: ControllableNetworkObserver()
            )
            model.setBudget(40, for: .anthropic)
            #expect(model.budget(for: .anthropic) == 40)

            model.setBudget(budget, for: .anthropic)

            #expect(model.budget(for: .anthropic) == nil)
        }
    }

    @Test func aRefreshEvaluatesAlertsForReadyHalves() async {
        configureAll()
        useHotReport()
        let model = makeModel()

        await model.refreshAll(manual: false)

        #expect(notifier.delivered.map { $0.key.hasSuffix(".80") } == [true])
    }

    @Test func providerAlertsOffDeliversNothing() async {
        configureAll()
        useHotReport()
        let model = makeModel()
        var settings = model.settings(for: .cursor)
        settings.alertsEnabled = false
        model.setSettings(settings, for: .cursor)

        await model.refreshAll(manual: false)

        #expect(notifier.delivered.isEmpty)
    }

    @Test func masterAlertsOffDeliversNothing() async {
        configureAll()
        useHotReport()
        let model = makeModel()
        model.setAlertsEnabled(false)

        await model.refreshAll(manual: false)

        #expect(notifier.delivered.isEmpty)
        #expect(!alertStore.isEnabled)
    }

    @Test func aFailedRefreshDoesNotAlertFromItsKeptReport() async {
        configureAll()
        useHotReport()
        let model = makeModel()
        var settings = model.settings(for: .cursor)
        settings.alertsEnabled = false
        model.setSettings(settings, for: .cursor)

        // A hot report is kept, with its alert keys forgotten so only the
        // status guard can keep the next pass quiet.
        await model.refreshAll(manual: false)
        for key in alertStore.keys {
            alertStore.clearDelivered(key)
        }
        settings.alertsEnabled = true
        model.setSettings(settings, for: .cursor)
        fetchers[.cursor]?.result = .failure(.transport)

        await model.refreshAll(manual: false)

        #expect(model.provider(.cursor).subscription?.report != nil)
        #expect(model.provider(.cursor).subscription?.status != .ready)
        #expect(notifier.delivered.isEmpty)
    }
}

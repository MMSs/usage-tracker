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
    private func makeAutoStartModel(
        starter: StubSessionFetcher, clock: Clock, autoStart: Bool = true, apiFetcher: StubReportFetcher? = nil
    ) -> AppModel {
        let providers = ProviderRegistry.all.map { descriptor in
            ProviderViewModel(
                descriptor: descriptor,
                subscriptionFetcher: descriptor.id == .anthropic ? starter : fetchers[descriptor.id],
                apiFetcher: descriptor.id == .anthropic ? apiFetcher : nil,
                credentialStore: credentials, cache: cache, now: { clock.date }
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

    @Test func aManualStartCountsTowardTheAutoStartWait() async {
        configureAll()
        let clock = Clock()
        let starter = StubSessionFetcher(fetchResult: .success(sessionReport(open: false, at: clock.date)))
        let model = makeAutoStartModel(starter: starter, clock: clock)
        await model.refreshAll(manual: true)

        // The popover's Start session button.
        await model.provider(.anthropic).subscription?.startSession()
        #expect(starter.startCount == 1)

        clock.date.addTimeInterval(5 * 60)
        await model.refreshAll(manual: false)
        #expect(model.provider(.anthropic).sessionIsClosed)
        #expect(starter.startCount == 1)

        clock.date.addTimeInterval(5 * 60)
        await model.refreshAll(manual: false)
        #expect(starter.startCount == 2)
    }

    @Test func autoStartPausesAfterThreeStartsLeaveTheSessionClosed() async {
        configureAll()
        let clock = Clock()
        let starter = StubSessionFetcher(fetchResult: .success(sessionReport(open: false, at: clock.date)))
        let model = makeAutoStartModel(starter: starter, clock: clock)

        for _ in 0..<3 {
            await model.refreshAll(manual: false)
            clock.date.addTimeInterval(AppModel.autoStartInterval)
        }
        #expect(starter.startCount == 3)

        await model.refreshAll(manual: false)
        clock.date.addTimeInterval(AppModel.autoStartInterval)
        await model.refreshAll(manual: false)
        #expect(model.provider(.anthropic).sessionIsClosed)
        #expect(starter.startCount == 3)

        // The Start session button still works.
        await model.provider(.anthropic).subscription?.startSession()
        #expect(starter.startCount == 4)
    }

    @Test func autoStartResumesOnceARefreshSeesTheSessionOpen() async {
        configureAll()
        let clock = Clock()
        let starter = StubSessionFetcher(fetchResult: .success(sessionReport(open: false, at: clock.date)))
        let model = makeAutoStartModel(starter: starter, clock: clock)
        for _ in 0..<4 {
            await model.refreshAll(manual: false)
            clock.date.addTimeInterval(AppModel.autoStartInterval)
        }
        #expect(starter.startCount == 3)

        starter.fetchResult = .success(sessionReport(open: true, at: clock.date))
        await model.refreshAll(manual: true)
        #expect(starter.startCount == 3)

        // The session ran out again: auto-start is back, with a fresh count.
        starter.fetchResult = .success(sessionReport(open: false, at: clock.date))
        for _ in 0..<4 {
            clock.date.addTimeInterval(AppModel.autoStartInterval)
            await model.refreshAll(manual: false)
        }
        #expect(starter.startCount == 6)
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

    @Test func aSwitchedOffSubscriptionHalfIsNotAutoStarted() async {
        configureAll()
        let clock = Clock()
        let starter = StubSessionFetcher(fetchResult: .success(sessionReport(open: false, at: clock.date)))
        let model = makeAutoStartModel(starter: starter, clock: clock)
        await model.refreshAll(manual: true)
        #expect(model.provider(.anthropic).sessionIsClosed)

        var settings = model.settings(for: .anthropic)
        settings.isSubscriptionEnabled = false
        model.setSettings(settings, for: .anthropic)
        await model.refreshAll(manual: false)

        #expect(starter.startCount == 0)
    }

    @Test func aScheduledAPIRefreshNeverAutoStarts() async {
        configureAll()
        credentials.values[CredentialKey(provider: .anthropic, fieldID: "admin-key")] = "adm"
        let clock = Clock()
        let starter = StubSessionFetcher(fetchResult: .success(sessionReport(open: false, at: clock.date)))
        let apiFetcher = StubReportFetcher(result: .success(makeReport(2)))
        let model = makeAutoStartModel(starter: starter, clock: clock, apiFetcher: apiFetcher)
        await model.refreshAll(manual: true)
        #expect(model.provider(.anthropic).sessionIsClosed)

        await model.refresh(RefreshTarget(provider: .anthropic, half: .api), manual: false)

        #expect(apiFetcher.callCount == 2)
        #expect(starter.startCount == 0)

        await model.refresh(RefreshTarget(provider: .anthropic, half: .subscription), manual: false)

        #expect(starter.startCount == 1)
    }

    @Test func aScheduledAPIRefreshLeavesThePlanUsageAlone() async {
        configureAll()
        credentials.values[CredentialKey(provider: .anthropic, fieldID: "admin-key")] = "adm"
        let apiFetcher = StubReportFetcher(result: .success(makeReport(2)))
        let model = makeModel(apiFetchers: [.anthropic: apiFetcher])

        await model.refresh(RefreshTarget(provider: .anthropic, half: .api), manual: false)

        #expect(apiFetcher.callCount == 1)
        #expect(fetchers[.anthropic]?.callCount == 0)
    }

    @Test func aSwitchedOffHalfHasNoSchedule() async {
        configureAll()
        credentials.values[CredentialKey(provider: .anthropic, fieldID: "admin-key")] = "adm"
        let model = makeModel(apiFetchers: [.anthropic: StubReportFetcher(result: .success(makeReport(2)))])
        model.setSettings(
            ProviderSettings(subscriptionRefreshInterval: .thirtySeconds, apiRefreshInterval: .oneHour, isAPIEnabled: false),
            for: .anthropic
        )

        model.start()
        await sleeper.waitForSleepCount(3)
        await settle()

        #expect(sleeper.durations.count == 3)
        #expect(!sleeper.durations.contains(.seconds(3600)))

        model.setSettings(
            ProviderSettings(subscriptionRefreshInterval: .thirtySeconds, apiRefreshInterval: .oneHour, isAPIEnabled: true),
            for: .anthropic
        )
        await sleeper.waitForSleepCount(4)

        #expect(sleeper.durations.last == .seconds(3600))

        model.scheduler.stop()
        sleeper.resume()
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
        let settings = ProviderSettings(isEnabled: false, subscriptionRefreshInterval: .oneHour, appearanceOverride: nil)

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

        model.setSettings(ProviderSettings(isEnabled: true, subscriptionRefreshInterval: .oneHour), for: .cursor)
        await settle()

        #expect(fetchers[.cursor]?.callCount == 1, "a change while already enabled does not refetch")
    }

    @Test func turningOnTheAPIHalfRefreshesOnlyIt() async {
        configureAll()
        credentials.values[CredentialKey(provider: .anthropic, fieldID: "admin-key")] = "adm"
        let clock = Clock()
        let starter = StubSessionFetcher(fetchResult: .success(sessionReport(open: false, at: clock.date)))
        let apiFetcher = StubReportFetcher(result: .success(makeReport(2)))
        let model = makeAutoStartModel(starter: starter, clock: clock, apiFetcher: apiFetcher)
        model.setSettings(ProviderSettings(isAPIEnabled: false, autoStartSessions: true), for: .anthropic)
        await settle()

        model.setSettings(ProviderSettings(isAPIEnabled: true, autoStartSessions: true), for: .anthropic)
        await waitUntil { apiFetcher.callCount == 1 }
        await settle()

        #expect(apiFetcher.callCount == 1)
        #expect(starter.fetchCount == 0)
        #expect(starter.startCount == 0)
    }

    @Test func turningOnAProviderRefreshesBothHalves() async {
        configureAll()
        credentials.values[CredentialKey(provider: .anthropic, fieldID: "admin-key")] = "adm"
        let apiFetcher = StubReportFetcher(result: .success(makeReport(2)))
        let model = makeModel(apiFetchers: [.anthropic: apiFetcher])
        model.setSettings(ProviderSettings(isEnabled: false), for: .anthropic)
        await settle()

        model.setSettings(ProviderSettings(isEnabled: true), for: .anthropic)
        await waitUntil { apiFetcher.callCount == 1 && fetchers[.anthropic]?.callCount == 1 }

        #expect(apiFetcher.callCount == 1)
        #expect(fetchers[.anthropic]?.callCount == 1)
    }

    @Test func turningOnAProviderSkipsItsOffHalf() async {
        configureAll()
        credentials.values[CredentialKey(provider: .anthropic, fieldID: "admin-key")] = "adm"
        let apiFetcher = StubReportFetcher(result: .success(makeReport(2)))
        let model = makeModel(apiFetchers: [.anthropic: apiFetcher])
        model.setSettings(ProviderSettings(isEnabled: false, isAPIEnabled: false), for: .anthropic)
        await settle()

        model.setSettings(ProviderSettings(isEnabled: true, isAPIEnabled: false), for: .anthropic)
        await waitUntil { fetchers[.anthropic]?.callCount == 1 }
        await settle()

        #expect(fetchers[.anthropic]?.callCount == 1)
        #expect(apiFetcher.callCount == 0)
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

    // MARK: Session reset alert

    private var sessionAlerts: [UsageAlert] {
        notifier.delivered.filter { $0.key.contains(".session.") }
    }

    /// A model that has seen an open Anthropic session, then the clock passes its
    /// reset and the fetcher reports the session closed.
    private func makeEndedSessionModel(
        autoStart: Bool = false, clock: Clock
    ) async -> (model: AppModel, starter: StubSessionFetcher) {
        configureAll()
        let starter = StubSessionFetcher(fetchResult: .success(sessionReport(open: true, at: clock.date)))
        let model = makeAutoStartModel(starter: starter, clock: clock, autoStart: autoStart)
        await model.refreshAll(manual: false)
        clock.date.addTimeInterval(3601)
        starter.fetchResult = .success(sessionReport(open: false, at: clock.date))

        return (model, starter)
    }

    private let scheduledSubscription = RefreshTarget(provider: .anthropic, half: .subscription)

    @Test func aSessionResetAlertsOnce() async {
        let clock = Clock()
        let (model, _) = await makeEndedSessionModel(clock: clock)

        await model.refresh(scheduledSubscription, manual: false)
        await model.refresh(scheduledSubscription, manual: false)

        #expect(sessionAlerts.map(\.title) == ["Anthropic session reset"])
        #expect(sessionAlerts.map(\.body) == ["You're back to 0%."])
    }

    @Test func theLaunchRefreshAlertsAnEndedSessionToo() async {
        let clock = Clock()
        let (model, _) = await makeEndedSessionModel(clock: clock)

        await model.refreshAll(manual: false)
        await model.refreshAll(manual: false)

        #expect(sessionAlerts.map(\.body) == ["You're back to 0%."])
    }

    @Test func autoStartMakesItOneCombinedAlert() async {
        let clock = Clock()
        let (model, starter) = await makeEndedSessionModel(autoStart: true, clock: clock)
        starter.afterStart = { [clock] in
            starter.fetchResult = .success(self.sessionReport(open: true, at: clock.date))
        }

        await model.refresh(scheduledSubscription, manual: false)

        #expect(starter.startCount == 1)
        #expect(sessionAlerts.map(\.body) == ["New session started."])
    }

    @Test func aFailedAutoStartKeepsThePlainAlert() async {
        let clock = Clock()
        let (model, starter) = await makeEndedSessionModel(autoStart: true, clock: clock)

        await model.refresh(scheduledSubscription, manual: false)

        #expect(starter.startCount == 1)
        #expect(sessionAlerts.map(\.body) == ["You're back to 0%."])
    }

    @Test func aManualRefreshPostsThePlainAlert() async {
        let clock = Clock()
        let (model, starter) = await makeEndedSessionModel(autoStart: true, clock: clock)

        await model.refresh(.anthropic, manual: true)

        #expect(starter.startCount == 0)
        #expect(sessionAlerts.map(\.body) == ["You're back to 0%."])
    }

    @Test func theSessionKindGatesIt() async {
        let clock = Clock()
        let (model, _) = await makeEndedSessionModel(clock: clock)
        model.setAlertKind(.session, enabled: false)

        await model.refreshAll(manual: false)
        model.setAlertKind(.session, enabled: true)
        await model.refreshAll(manual: false)

        #expect(sessionAlerts.isEmpty)
    }

    @Test func cursorNeverPostsASessionAlert() async {
        configureAll()
        let clock = Clock()
        fetchers[.cursor]?.result = .success(sessionReport(open: true, at: clock.date))
        let starter = StubSessionFetcher(fetchResult: .success(sessionReport(open: true, at: clock.date)))
        let model = makeAutoStartModel(starter: starter, clock: clock)
        await model.refreshAll(manual: false)
        clock.date.addTimeInterval(3601)
        fetchers[.cursor]?.result = .success(sessionReport(open: false, at: clock.date))
        starter.fetchResult = .success(sessionReport(open: true, at: clock.date))

        await model.refreshAll(manual: false)

        #expect(sessionAlerts.filter { $0.title.hasPrefix("Cursor") }.isEmpty)
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

    @Test func startAsksForPermissionWhenAlertsAreOn() {
        let model = makeModel()

        model.start()

        #expect(notifier.authorizationRequests == 1)
    }

    @Test func startDoesNotAskWhenEveryKindIsOff() {
        for kind in AlertKind.allCases {
            alertStore.setEnabled(false, for: kind)
        }
        let model = makeModel()

        model.start()

        #expect(notifier.authorizationRequests == 0)
    }

    @Test func startDoesNotAskWhenTheMasterIsOff() {
        alertStore.isEnabled = false
        let model = makeModel()

        model.start()

        #expect(notifier.authorizationRequests == 0)
    }

    @Test func turningAKindOnAsks() {
        alertStore.setEnabled(false, for: .failures)
        let model = makeModel()

        model.setAlertKind(.failures, enabled: true)

        #expect(model.alertKinds.contains(.failures))
        #expect(alertStore.isEnabled(.failures))
        #expect(notifier.authorizationRequests == 1)
    }

    @Test func usageAlertsFollowTheirKind() async {
        configureAll()
        useHotReport()
        let model = makeModel()
        model.setAlertKind(.usage, enabled: false)

        await model.refreshAll(manual: false)

        #expect(notifier.delivered.isEmpty)
        #expect(!alertStore.keys.isEmpty)

        model.setAlertKind(.usage, enabled: true)
        await model.refreshAll(manual: false)

        #expect(notifier.delivered.isEmpty)
    }

    @Test func aSwitchedOffHalfDoesNotAlertFromItsKeptReport() async {
        configureAll()
        useHotReport()
        let model = makeModel()
        var settings = model.settings(for: .cursor)
        settings.alertsEnabled = false
        model.setSettings(settings, for: .cursor)

        // A hot report is kept, with its alert keys forgotten so only the
        // switched-off half can keep the next pass quiet.
        await model.refreshAll(manual: false)
        for key in alertStore.keys {
            alertStore.clearDelivered(key)
        }
        settings.alertsEnabled = true
        settings.isSubscriptionEnabled = false
        model.setSettings(settings, for: .cursor)

        await model.refreshAll(manual: false)

        #expect(model.provider(.cursor).subscription?.status == .ready)
        #expect(notifier.delivered.isEmpty)
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

    // MARK: Refresh failure alert

    private var failureAlerts: [UsageAlert] {
        notifier.delivered.filter { $0.key.hasSuffix(".failure") }
    }

    @Test func aFailingHalfAlertsOncePerStreak() async {
        configureAll()
        let model = makeModel()
        model.setAlertKind(.failures, enabled: true)
        fetchers[.cursor]?.result = .failure(.unauthorized)

        await model.refreshAll(manual: false)
        await model.refresh(RefreshTarget(provider: .cursor, half: .subscription), manual: true)
        await model.refresh(RefreshTarget(provider: .cursor, half: .subscription), manual: true)

        #expect(failureAlerts.map(\.title) == ["Cursor plan usage couldn't refresh"])
        #expect(failureAlerts.map(\.body) == ["Credential expired."])

        fetchers[.cursor]?.result = .success(makeReport(1))
        await model.refresh(RefreshTarget(provider: .cursor, half: .subscription), manual: true)
        fetchers[.cursor]?.result = .failure(.unauthorized)
        await model.refresh(RefreshTarget(provider: .cursor, half: .subscription), manual: true)

        #expect(failureAlerts.count == 2)
    }

    @Test func aProviderRefreshAlertsForEachFailingHalf() async {
        configureAll()
        credentials.values[CredentialKey(provider: .anthropic, fieldID: "admin-key")] = "adm"
        let apiFetcher = StubReportFetcher(result: .failure(.httpStatus(500)))
        let model = makeModel(apiFetchers: [.anthropic: apiFetcher])
        model.setAlertKind(.failures, enabled: true)
        fetchers[.anthropic]?.result = .failure(.unauthorized)

        await model.refresh(.anthropic, manual: true)

        #expect(Set(failureAlerts.map(\.key)) == ["anthropic.subscription.failure", "anthropic.api.failure"])
        #expect(fetchers[.cursor]?.callCount == 0)
    }

    @Test func offlineFailuresNeverAlert() async {
        configureAll()
        let model = makeModel()
        model.setAlertKind(.failures, enabled: true)
        fetchers[.cursor]?.result = .failure(.offline)

        await model.refreshAll(manual: false)

        #expect(failureAlerts.isEmpty)
    }

    @Test func aTimeoutAlerts() async {
        configureAll()
        let model = makeModel()
        model.setAlertKind(.failures, enabled: true)
        fetchers[.cursor]?.result = .failure(.transport)

        await model.refreshAll(manual: false)

        #expect(failureAlerts.map(\.body) == ["Couldn't reach the server."])
    }

    @Test func goingOfflineDoesNotEndAStreak() async {
        configureAll()
        let model = makeModel()
        model.setAlertKind(.failures, enabled: true)
        let target = RefreshTarget(provider: .cursor, half: .subscription)
        fetchers[.cursor]?.result = .failure(.unauthorized)
        await model.refresh(target, manual: true)
        fetchers[.cursor]?.result = .failure(.offline)
        await model.refresh(target, manual: true)
        fetchers[.cursor]?.result = .failure(.unauthorized)
        await model.refresh(target, manual: true)

        #expect(failureAlerts.count == 1)
    }

    @Test func theFailuresKindGatesIt() async {
        configureAll()
        let model = makeModel()
        fetchers[.cursor]?.result = .failure(.unauthorized)

        await model.refreshAll(manual: false)

        #expect(failureAlerts.isEmpty)
    }

    @Test func eachHalfHasItsOwnStreak() async {
        configureAll()
        credentials.values[CredentialKey(provider: .anthropic, fieldID: "admin-key")] = "adm"
        let apiFetcher = StubReportFetcher(result: .failure(.httpStatus(500)))
        let model = makeModel(apiFetchers: [.anthropic: apiFetcher])
        model.setAlertKind(.failures, enabled: true)
        fetchers[.anthropic]?.result = .failure(.unauthorized)

        await model.refreshAll(manual: false)
        await model.refresh(RefreshTarget(provider: .anthropic, half: .api), manual: true)

        #expect(Set(failureAlerts.map(\.key)) == ["anthropic.subscription.failure", "anthropic.api.failure"])
        #expect(failureAlerts.count == 2)

        fetchers[.anthropic]?.result = .success(makeReport(2))
        await model.refresh(RefreshTarget(provider: .anthropic, half: .subscription), manual: true)
        fetchers[.anthropic]?.result = .failure(.unauthorized)
        await model.refresh(RefreshTarget(provider: .anthropic, half: .subscription), manual: true)
        await model.refresh(RefreshTarget(provider: .anthropic, half: .api), manual: true)

        #expect(failureAlerts.count == 3, "only the plan usage half started a new streak")
    }
}

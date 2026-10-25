import Combine
import Foundation
import os

/// Composition root: owns the providers, the refresh scheduler, and the
/// settings stores.
@MainActor
final class AppModel: ObservableObject {
    let providers: [ProviderViewModel]
    let credentialStore: CredentialStoring
    let providerSettingsStore: ProviderSettingsStoring
    let appearanceStore: MenuBarAppearanceStoring
    private let budgetStore: APIBudgetStoring
    private let alertMonitor: AlertMonitor?
    private let now: () -> Date
    let loginItem: LoginItemModel
    private(set) var scheduler: RefreshScheduler!
    /// Set by the app delegate; opens the Settings window. A no-op until then.
    var presentSettings: (SettingsRequest) -> Void = { _ in }

    /// The appearance every provider uses unless it overrides it.
    @Published private(set) var globalAppearance: MenuBarAppearance
    @Published private(set) var providerSettings: [Provider: ProviderSettings]
    /// Monthly API budgets that are set. The store alone would publish nothing.
    @Published private(set) var apiBudgets: [Provider: Decimal]
    /// The master switch for usage alerts.
    @Published private(set) var alertsEnabled: Bool

    /// The least time between two automatic session starts for one provider.
    static let autoStartInterval: TimeInterval = 600
    /// Automatic starts in a row that may each leave the session closed
    /// before auto-start pauses until a refresh sees the session open.
    static let autoStartPauseAfter = 3

    private var isStarted = false
    /// Automatic starts in a row whose next check still found the session closed.
    private var unopenedAutoStarts: [Provider: Int] = [:]
    /// Providers whose last automatic start has not been checked yet.
    private var autoStartsAwaitingCheck: Set<Provider> = []
    private var providerObservers: [AnyCancellable] = []

    init(
        providers: [ProviderViewModel],
        credentialStore: CredentialStoring,
        providerSettingsStore: ProviderSettingsStoring,
        appearanceStore: MenuBarAppearanceStoring,
        budgetStore: APIBudgetStoring,
        loginItem: LoginItemModel,
        sleepObserver: SystemSleepObserving,
        networkObserver: NetworkReachabilityObserving,
        sleep: @escaping RefreshScheduler.Sleep = { duration in
            try? await Task.sleep(for: duration)
        },
        now: @escaping () -> Date = Date.init,
        alertMonitor: AlertMonitor? = nil
    ) {
        self.providers = providers
        self.credentialStore = credentialStore
        self.providerSettingsStore = providerSettingsStore
        self.appearanceStore = appearanceStore
        self.budgetStore = budgetStore
        self.loginItem = loginItem
        self.now = now
        self.alertMonitor = alertMonitor
        alertsEnabled = alertMonitor?.isEnabled ?? true
        globalAppearance = appearanceStore.appearance()
        providerSettings = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, providerSettingsStore.settings(for: $0.id)) })
        apiBudgets = Dictionary(uniqueKeysWithValues: providers.compactMap { provider in
            budgetStore.budget(for: provider.id).map { (provider.id, $0) }
        })

        for provider in providers {
            Self.apply(providerSettings[provider.id] ?? .default, to: provider)
        }

        // Forward provider changes so the menu bar scenes re-evaluate `insertedProviders`.
        providerObservers = providers.map { provider in
            provider.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        }

        // The scheduler is owned by the model, so its closures hold the model weakly.
        scheduler = RefreshScheduler(
            schedules: Self.schedules(providers, settings: providerSettings),
            initialRefresh: { [weak self] in await self?.refreshAll(manual: false) },
            periodicRefresh: { [weak self] target in await self?.refresh(target, manual: false) },
            sleepObserver: sleepObserver,
            networkObserver: networkObserver,
            sleep: sleep
        )
    }

    func start() {
        guard !isStarted else {
            return
        }

        isStarted = true
        scheduler.start()
    }

    /// Refreshes every enabled provider; disabled ones keep their last report untouched.
    func refreshAll(manual: Bool) async {
        await withTaskGroup(of: Void.self) { group in
            for provider in providers where provider.isEnabled {
                group.addTask {
                    await provider.refresh(manual: manual)
                }
            }
        }

        for provider in providers where provider.isEnabled {
            evaluateAlerts(for: provider)
            noteOpenSession(provider)
        }

        // A manual refresh only looks; it never starts a session.
        guard !manual else {
            return
        }

        for provider in providers where provider.isEnabled {
            await autoStartIfNeeded(provider)
        }
    }

    /// Refreshes one half of a provider. Only the plan usage half takes part in
    /// the session bookkeeping and auto-start; the API spend half never does.
    func refresh(_ target: RefreshTarget, manual: Bool) async {
        let provider = provider(target.provider)
        guard provider.isEnabled else {
            Log.refresh.debug("\(target.provider.rawValue, privacy: .public): skipped, provider switched off")
            return
        }

        await provider.refresh(target.half, manual: manual)
        evaluateAlerts(for: provider, halves: [target.half])
        guard target.half == .subscription else {
            return
        }

        noteOpenSession(provider)
        if !manual {
            await autoStartIfNeeded(provider)
        }
    }

    // MARK: Session start

    /// Starts the provider's closed session when the user turned that on, at
    /// most once per `autoStartInterval` after any start attempt, the Start
    /// session button's included. `sessionIsClosed` already requires
    /// a switched-on, up-to-date subscription half, so a switched-off, expired
    /// or errored one is skipped. After `autoStartPauseAfter` starts in a row
    /// that each left the session closed, it waits for the session to open.
    private func autoStartIfNeeded(_ provider: ProviderViewModel) async {
        let id = provider.id
        guard settings(for: id).autoStartSessions,
              provider.sessionIsClosed,
              let subscription = provider.subscription
        else {
            return
        }

        if autoStartsAwaitingCheck.remove(id) != nil {
            let unopened = unopenedAutoStarts[id, default: 0] + 1
            unopenedAutoStarts[id] = unopened
            if unopened == Self.autoStartPauseAfter {
                Log.refresh.notice("\(id.rawValue, privacy: .public): auto-start paused after \(unopened, privacy: .public) starts left the session closed")
            }
        }

        guard unopenedAutoStarts[id, default: 0] < Self.autoStartPauseAfter else {
            return
        }

        if let last = subscription.lastSessionStartAttempt, now().timeIntervalSince(last) < Self.autoStartInterval {
            return
        }

        autoStartsAwaitingCheck.insert(id)
        await subscription.startSession()
    }

    /// A running session shows starts can open it (or it was used): any
    /// auto-start pause ends and the count starts afresh.
    private func noteOpenSession(_ provider: ProviderViewModel) {
        guard provider.sessionIsOpen else {
            return
        }

        unopenedAutoStarts[provider.id] = nil
        autoStartsAwaitingCheck.remove(provider.id)
    }

    // MARK: Alerts

    func setAlertsEnabled(_ enabled: Bool) {
        alertMonitor?.isEnabled = enabled
        alertsEnabled = alertMonitor?.isEnabled ?? enabled
    }

    /// Checks each enabled, ready half against the alert thresholds. A half
    /// in error or switched off keeps its last report but is not evaluated,
    /// so a stale figure never alerts. Only the given halves are looked at.
    private func evaluateAlerts(for provider: ProviderViewModel, halves: Set<Half> = [.subscription, .api]) {
        guard let alertMonitor else {
            return
        }

        let delivers = alertsEnabled && settings(for: provider.id).alertsEnabled

        for model in [provider.subscription, provider.api].compactMap({ $0 }) where halves.contains(model.half) && model.isEnabled && model.status == .ready {
            guard let report = model.report else {
                continue
            }

            let measures = AlertPolicy.measures(
                descriptor: provider.descriptor,
                half: model.half,
                report: report,
                budget: budget(for: provider.id),
                now: now()
            )
            alertMonitor.evaluate(measures, delivers: delivers)
        }
    }

    // MARK: Settings

    func settings(for provider: Provider) -> ProviderSettings {
        providerSettings[provider] ?? .default
    }

    func setSettings(_ settings: ProviderSettings, for id: Provider) {
        let provider = provider(id)
        let wasOn = Self.enabledFlags(provider)
        providerSettings[id] = settings
        providerSettingsStore.setSettings(settings, for: id)
        Self.apply(settings, to: provider)
        for half in [Half.subscription, .api] {
            scheduler.setSchedule(Self.interval(settings, half, of: provider), for: RefreshTarget(provider: id, half: half))
        }

        // Turning something on should show data now, not after the next timer tick.
        let turnedOn = zip(wasOn, Self.enabledFlags(provider)).contains { !$0 && $1 }
        if settings.isEnabled, turnedOn {
            Task {
                for half in [Half.subscription, .api] {
                    await refresh(RefreshTarget(provider: id, half: half), manual: false)
                }
            }
        }
    }

    private static func apply(_ settings: ProviderSettings, to provider: ProviderViewModel) {
        provider.isEnabled = settings.isEnabled
        provider.subscription?.isEnabled = settings.isSubscriptionEnabled
        provider.api?.isEnabled = settings.isAPIEnabled
    }

    private static func enabledFlags(_ provider: ProviderViewModel) -> [Bool] {
        [provider.isEnabled, provider.subscription?.isEnabled ?? false, provider.api?.isEnabled ?? false]
    }

    func setGlobalAppearance(_ appearance: MenuBarAppearance) {
        globalAppearance = appearance
        appearanceStore.setAppearance(appearance)
    }

    /// The provider's override when it has one, else the global appearance.
    func appearance(for provider: Provider) -> MenuBarAppearance {
        settings(for: provider).appearanceOverride ?? globalAppearance
    }

    /// The interval for one half's timer; nil when the provider or the half is off or missing.
    private static func interval(_ settings: ProviderSettings, _ half: Half, of provider: ProviderViewModel) -> RefreshInterval? {
        guard settings.isEnabled, settings.isEnabled(half), provider.half(half) != nil else {
            return nil
        }

        return settings.refreshInterval(for: half)
    }

    private static func schedules(
        _ providers: [ProviderViewModel], settings: [Provider: ProviderSettings]
    ) -> [RefreshTarget: RefreshInterval] {
        var schedules: [RefreshTarget: RefreshInterval] = [:]
        for provider in providers {
            let providerSettings = settings[provider.id] ?? .default
            for half in [Half.subscription, .api] {
                schedules[RefreshTarget(provider: provider.id, half: half)] = interval(providerSettings, half, of: provider)
            }
        }
        return schedules
    }

    // MARK: API budget

    func budget(for provider: Provider) -> Decimal? {
        apiBudgets[provider]
    }

    /// Saves the budget and republishes what the store kept, so the menu bar
    /// and popover redraw now rather than at the next refresh.
    func setBudget(_ budget: Decimal?, for provider: Provider) {
        budgetStore.setBudget(budget, for: provider)
        apiBudgets[provider] = budgetStore.budget(for: provider)
    }

    // MARK: Menu bar

    /// Enabled providers with an enabled, configured half, in registry
    /// order. When nothing is configured, the first provider alone, so there
    /// is always an item to click. When everything configured is switched
    /// off, nothing: the app is reached by opening it.
    var insertedProviders: [Provider] {
        guard !showsSetUpItem else {
            return [ProviderRegistry.all[0].id]
        }

        return providers.filter { $0.isConfigured && $0.isEnabled && $0.hasActiveHalf }.map(\.id)
    }

    /// Items in the order the menu bar shows them, left to right. NSStatusBar
    /// puts each newly inserted item to the left of the others, so that is
    /// the registry (insertion) order reversed. A Cmd-drag rearrangement
    /// cannot be seen here.
    static func menuBarDisplayOrder<Element>(_ elements: [Element]) -> [Element] {
        elements.reversed()
    }

    /// True while nothing is configured, so the menu bar holds only the first
    /// provider's set-up item rather than any usage.
    var showsSetUpItem: Bool {
        !providers.contains(where: \.isConfigured)
    }

    func provider(_ id: Provider) -> ProviderViewModel {
        providers.first { $0.id == id }!
    }

    /// The report services behind each provider's halves.
    private static func fetchers(
        for provider: Provider,
        organizationStore: OrganizationSelectionStoring,
        credentialStore: CredentialStoring,
        models: SessionModelStoring
    ) -> (subscription: ReportFetching?, api: ReportFetching?) {
        switch provider {
        case .cursor:
            (CursorReportService(service: CursorUsageService()), nil)
        case .anthropic:
            (
                AnthropicSubscriptionReportService(
                    service: AnthropicUsageService(),
                    selectionStore: organizationStore,
                    models: models
                ),
                AnthropicAPIReportService(service: AnthropicCostService())
            )
        case .openai:
            (
                OpenAISubscriptionReportService(
                    usage: OpenAIUsageService(),
                    tokens: OpenAITokenService(),
                    credentialStore: credentialStore,
                    models: models
                ),
                OpenAIAPIReportService(service: OpenAICostService())
            )
        }
    }

    static func live() -> AppModel {
        // Before any store reads, so they see the migrated credentials and settings.
        IdentifierMigration.live().run()

        let credentialStore = KeychainCredentialStore()
        let cache = UserDefaultsReportCache()
        let history = UserDefaultsUsageHistoryStore()
        // Read and written only by the organization-scoped fetchers.
        let organizationStore = UserDefaultsOrganizationSelectionStore()

        let models = UserDefaultsSessionModelStore()

        let providers = ProviderRegistry.all.map { descriptor in
            let fetchers = fetchers(
                for: descriptor.id,
                organizationStore: organizationStore,
                credentialStore: credentialStore,
                models: models
            )
            return ProviderViewModel(
                descriptor: descriptor,
                subscriptionFetcher: fetchers.subscription,
                apiFetcher: fetchers.api,
                credentialStore: credentialStore,
                cache: cache,
                history: history
            )
        }

        return AppModel(
            providers: providers,
            credentialStore: credentialStore,
            providerSettingsStore: UserDefaultsProviderSettingsStore(),
            appearanceStore: UserDefaultsMenuBarAppearanceStore(),
            budgetStore: UserDefaultsAPIBudgetStore(),
            loginItem: LoginItemModel(manager: LoginItemManager(), store: UserDefaultsLoginItemPreferenceStore()),
            sleepObserver: SystemSleepObserver(),
            networkObserver: NetworkReachabilityObserver(),
            alertMonitor: AlertMonitor(notifier: SystemUsageNotifier(), store: UserDefaultsAlertStateStore())
        )
    }
}

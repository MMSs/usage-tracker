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
    let loginItem: LoginItemModel
    private(set) var scheduler: RefreshScheduler!
    /// Set by the app delegate; opens the Settings window. A no-op until then.
    var presentSettings: (SettingsRequest) -> Void = { _ in }

    /// The appearance every provider uses unless it overrides it.
    @Published private(set) var globalAppearance: MenuBarAppearance
    @Published private(set) var providerSettings: [Provider: ProviderSettings]
    /// Monthly API budgets that are set. The store alone would publish nothing.
    @Published private(set) var apiBudgets: [Provider: Decimal]

    private var isStarted = false
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
        }
    ) {
        self.providers = providers
        self.credentialStore = credentialStore
        self.providerSettingsStore = providerSettingsStore
        self.appearanceStore = appearanceStore
        self.budgetStore = budgetStore
        self.loginItem = loginItem
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
            schedules: Self.schedules(providerSettings),
            initialRefresh: { [weak self] in await self?.refreshAll(manual: false) },
            periodicRefresh: { [weak self] provider in await self?.refresh(provider, manual: false) },
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
    }

    private func refresh(_ id: Provider, manual: Bool) async {
        let provider = provider(id)
        guard provider.isEnabled else {
            Log.refresh.debug("\(id.rawValue, privacy: .public): skipped, provider switched off")
            return
        }

        await provider.refresh(manual: manual)
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
        scheduler.setSchedule(settings.isEnabled ? settings.refreshInterval : nil, for: id)

        // Turning something on should show data now, not after the next timer tick.
        let turnedOn = zip(wasOn, Self.enabledFlags(provider)).contains { !$0 && $1 }
        if settings.isEnabled, turnedOn {
            Task { await refresh(id, manual: false) }
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

    private static func schedules(_ settings: [Provider: ProviderSettings]) -> [Provider: RefreshInterval] {
        settings.filter { $0.value.isEnabled }.mapValues(\.refreshInterval)
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

    /// True while nothing is configured, so the menu bar holds only the first
    /// provider's set-up item rather than any usage.
    var showsSetUpItem: Bool {
        !providers.contains(where: \.isConfigured)
    }

    func provider(_ id: Provider) -> ProviderViewModel {
        providers.first { $0.id == id }!
    }

    /// The report services behind each provider's halves. OpenAI has none yet.
    private static func fetchers(
        for provider: Provider,
        organizationStore: OrganizationSelectionStoring
    ) -> (subscription: ReportFetching?, api: ReportFetching?) {
        switch provider {
        case .cursor:
            (CursorReportService(service: CursorUsageService()), nil)
        case .anthropic:
            (
                AnthropicSubscriptionReportService(service: AnthropicUsageService(), selectionStore: organizationStore),
                AnthropicAPIReportService(service: AnthropicCostService())
            )
        case .openai:
            (nil, nil)
        }
    }

    static func live() -> AppModel {
        // Before any store reads, so they see the migrated credentials and settings.
        IdentifierMigration.live().run()

        let credentialStore = KeychainCredentialStore()
        let cache = UserDefaultsReportCache()
        // Read and written only by the organization-scoped fetchers.
        let organizationStore = UserDefaultsOrganizationSelectionStore()

        let providers = ProviderRegistry.all.map { descriptor in
            let fetchers = fetchers(for: descriptor.id, organizationStore: organizationStore)
            return ProviderViewModel(
                descriptor: descriptor,
                subscriptionFetcher: fetchers.subscription,
                apiFetcher: fetchers.api,
                credentialStore: credentialStore,
                cache: cache
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
            networkObserver: NetworkReachabilityObserver()
        )
    }
}

import Combine
import Foundation

/// Composition root: owns the providers, the refresh scheduler, and the
/// settings stores.
@MainActor
final class AppModel: ObservableObject {
    let providers: [ProviderViewModel]
    let credentialStore: CredentialStoring
    let providerSettingsStore: ProviderSettingsStoring
    let appearanceStore: MenuBarAppearanceStoring
    let budgetStore: APIBudgetStoring
    private(set) var scheduler: RefreshScheduler!
    /// Set by the app delegate; opens the Settings window. A no-op until then.
    var presentSettings: (SettingsRequest) -> Void = { _ in }

    /// The appearance every provider uses unless it overrides it.
    @Published private(set) var globalAppearance: MenuBarAppearance
    @Published private(set) var providerSettings: [Provider: ProviderSettings]

    private var isStarted = false
    private var providerObservers: [AnyCancellable] = []

    init(
        providers: [ProviderViewModel],
        credentialStore: CredentialStoring,
        providerSettingsStore: ProviderSettingsStoring,
        appearanceStore: MenuBarAppearanceStoring,
        budgetStore: APIBudgetStoring,
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
        globalAppearance = appearanceStore.appearance()
        providerSettings = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, providerSettingsStore.settings(for: $0.id)) })

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

    // MARK: Menu bar

    /// Enabled providers with an enabled, configured half, in registry
    /// order. When nothing is configured, the first provider alone, so there
    /// is always an item to click. When everything configured is switched
    /// off, nothing: the app is reached by opening it.
    var insertedProviders: [Provider] {
        let configured = providers.filter(\.isConfigured)
        guard !configured.isEmpty else {
            return [ProviderRegistry.all[0].id]
        }

        return configured.filter { $0.isEnabled && $0.hasActiveHalf }.map(\.id)
    }

    func provider(_ id: Provider) -> ProviderViewModel {
        providers.first { $0.id == id }!
    }

    static func live() -> AppModel {
        let credentialStore = KeychainCredentialStore()
        let cache = UserDefaultsReportCache()

        let providers = ProviderRegistry.all.map { descriptor in
            ProviderViewModel(
                descriptor: descriptor,
                subscriptionFetcher: descriptor.id == .cursor
                    ? CursorReportService(service: CursorUsageService())
                    : nil,
                apiFetcher: nil,
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
            sleepObserver: SystemSleepObserver(),
            networkObserver: NetworkReachabilityObserver()
        )
    }
}

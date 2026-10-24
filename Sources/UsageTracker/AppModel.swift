import Combine
import Foundation

/// Composition root: owns the providers, the refresh scheduler, and the
/// settings stores.
@MainActor
final class AppModel: ObservableObject {
    let providers: [ProviderViewModel]
    let credentialStore: CredentialStoring
    let intervalStore: RefreshIntervalStoring
    let appearanceStore: MenuBarAppearanceStoring
    let budgetStore: APIBudgetStoring
    private(set) var scheduler: RefreshScheduler!
    /// Set by the app delegate; opens the Settings window. A no-op until then.
    var presentSettings: (SettingsRequest) -> Void = { _ in }

    private var isStarted = false
    private var providerObservers: [AnyCancellable] = []

    init(
        providers: [ProviderViewModel],
        credentialStore: CredentialStoring,
        intervalStore: RefreshIntervalStoring,
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
        self.intervalStore = intervalStore
        self.appearanceStore = appearanceStore
        self.budgetStore = budgetStore

        // Forward provider changes so the menu bar scenes re-evaluate `insertedProviders`.
        providerObservers = providers.map { provider in
            provider.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        }

        // The scheduler is owned by the model, so its closures hold the model weakly.
        scheduler = RefreshScheduler(
            interval: intervalStore.interval(),
            initialRefresh: { [weak self] in await self?.refreshAll(manual: false) },
            periodicRefresh: { [weak self] in await self?.refreshAll(manual: false) },
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

    func refreshAll(manual: Bool) async {
        await withTaskGroup(of: Void.self) { group in
            for provider in providers {
                group.addTask {
                    await provider.refresh(manual: manual)
                }
            }
        }
    }

    func setInterval(_ interval: RefreshInterval) {
        intervalStore.setInterval(interval)
        scheduler.setInterval(interval)
    }

    /// Configured providers in registry order; the first provider alone when none is
    /// configured, so there is always an item to click.
    var insertedProviders: [Provider] {
        let configured = providers.filter(\.isConfigured).map(\.id)
        return configured.isEmpty ? [ProviderRegistry.all[0].id] : configured
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
            intervalStore: UserDefaultsRefreshIntervalStore(),
            appearanceStore: UserDefaultsMenuBarAppearanceStore(),
            budgetStore: UserDefaultsAPIBudgetStore(),
            sleepObserver: SystemSleepObserver(),
            networkObserver: NetworkReachabilityObserver()
        )
    }
}

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
    let updates: UpdatesModel
    /// Nil when the app runs without sync (tests, previews).
    let sync: SyncCoordinator?
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
    /// The alert kinds that are switched on.
    @Published private(set) var alertKinds: Set<AlertKind>

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
    /// The reset of each provider's session as last seen open.
    private var lastOpenSessionReset: [Provider: Date] = [:]
    /// Halves whose refreshes are failing, so a streak alerts once.
    private var failingTargets: Set<RefreshTarget> = []
    private var providerObservers: [AnyCancellable] = []

    init(
        providers: [ProviderViewModel],
        credentialStore: CredentialStoring,
        providerSettingsStore: ProviderSettingsStoring,
        appearanceStore: MenuBarAppearanceStoring,
        budgetStore: APIBudgetStoring,
        loginItem: LoginItemModel,
        updates: UpdatesModel = UpdatesModel(updater: nil, build: BuildInfo(infoDictionary: nil)),
        sleepObserver: SystemSleepObserving,
        networkObserver: NetworkReachabilityObserving,
        sleep: @escaping RefreshScheduler.Sleep = { duration in
            try? await Task.sleep(for: duration)
        },
        now: @escaping () -> Date = Date.init,
        alertMonitor: AlertMonitor? = nil,
        sync: SyncCoordinator? = nil
    ) {
        self.providers = providers
        self.credentialStore = credentialStore
        self.providerSettingsStore = providerSettingsStore
        self.appearanceStore = appearanceStore
        self.budgetStore = budgetStore
        self.loginItem = loginItem
        self.updates = updates
        self.now = now
        self.alertMonitor = alertMonitor
        self.sync = sync
        alertsEnabled = alertMonitor?.isEnabled ?? true
        alertKinds = Set(AlertKind.allCases.filter { alertMonitor?.isEnabled($0) ?? $0.defaultEnabled })
        globalAppearance = appearanceStore.appearance()
        providerSettings = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, Self.loadSettings(of: $0, from: providerSettingsStore)) })
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
        sync?.delegate = self
    }

    func start() {
        guard !isStarted else {
            return
        }

        isStarted = true
        if let sync {
            Task { await sync.start() }
        }
        scheduler.start()

        if alertsEnabled, !alertKinds.isEmpty {
            alertMonitor?.requestAuthorization()
        }
    }

    /// Refreshes every enabled provider; disabled ones keep their last report untouched.
    func refreshAll(manual: Bool) async {
        // Each half takes its own turn with the other Macs.
        if sync?.mode.sharesUsage == true {
            await refreshEachHalf(manual: manual)
            return
        }

        let started = now()
        await withTaskGroup(of: Void.self) { group in
            for provider in providers where provider.isEnabled {
                group.addTask {
                    await provider.refresh(manual: manual)
                }
            }
        }

        var ended: [Provider: Date] = [:]
        for provider in providers where provider.isEnabled {
            evaluateAlerts(for: provider)
            trackFailures(of: provider, halves: [.subscription, .api], since: started)
            noteOpenSession(provider)
            ended[provider.id] = endedSession(of: provider)
        }

        for provider in providers where provider.isEnabled {
            // A manual refresh only looks; it never starts a session.
            if !manual {
                await autoStartIfNeeded(provider)
            }
            finishSession(of: provider, endedAt: ended[provider.id])
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

        if !manual, let sync, await sync.prepareScheduledFetch(target, interval: scheduledInterval(target)) == .skip {
            return
        }

        let refreshStart = now()
        await provider.refresh(target.half, manual: manual)
        if let sync {
            let fetched = provider.half(target.half)?.sharedState?.updatedAt.map { $0 >= refreshStart } ?? false
            await sync.publishRefresh(target, fetched: fetched)
        }
        evaluateAlerts(for: provider, halves: [target.half])
        trackFailures(of: provider, halves: [target.half], since: refreshStart)
        guard target.half == .subscription else {
            return
        }

        noteOpenSession(provider)
        let ended = endedSession(of: provider)
        if !manual {
            await autoStartIfNeeded(provider)
        }
        finishSession(of: provider, endedAt: ended)
    }

    /// Refreshes each switched-on half of one provider together, as the
    /// popover's Refresh button does, with the bookkeeping of a one-half refresh.
    /// True when no refreshed half ended with a failure recorded by this refresh.
    @discardableResult
    func refresh(_ id: Provider, manual: Bool) async -> Bool {
        let provider = provider(id)
        let halves = [Half.subscription, .api].filter { provider.half($0)?.isEnabled == true }
        let refreshStart = now()
        await withTaskGroup(of: Void.self) { group in
            for half in halves {
                group.addTask { await self.refresh(RefreshTarget(provider: id, half: half), manual: manual) }
            }
        }

        return !halves.contains { half in
            guard let failure = provider.half(half)?.lastFailure else {
                return false
            }

            return failure.date >= refreshStart
        }
    }

    /// Refreshes each switched-on half on its own, so each takes its turn with the other Macs.
    private func refreshEachHalf(manual: Bool) async {
        let targets = providers.filter(\.isEnabled).flatMap { provider in
            [Half.subscription, .api].filter { provider.half($0)?.isEnabled == true }.map { RefreshTarget(provider: provider.id, half: $0) }
        }

        await withTaskGroup(of: Void.self) { group in
            for target in targets {
                group.addTask { await self.refresh(target, manual: manual) }
            }
        }
    }

    private func scheduledInterval(_ target: RefreshTarget) -> TimeInterval {
        TimeInterval(settings(for: target.provider).refreshInterval(for: target.half).seconds)
    }

    /// Another Mac's outcome for the half, taken as if refreshed here, with a
    /// refresh's alerts and session bookkeeping. Never an automatic session
    /// start: the Mac that fetched decides that.
    func adoptRefresh(_ state: SharedHalfState, for target: RefreshTarget) {
        let provider = provider(target.provider)
        guard provider.isEnabled, provider.adopt(state, for: target.half) else {
            return
        }

        evaluateAlerts(for: provider, halves: [target.half])
        trackFailures(of: provider, halves: [target.half], since: .distantPast)
        guard target.half == .subscription else {
            return
        }

        noteOpenSession(provider)
        finishSession(of: provider, endedAt: endedSession(of: provider))
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

        // Another Mac may have started it, or be starting it now.
        if let sync, !(await sync.claimSessionStart(id, within: Self.autoStartInterval)) {
            return
        }

        autoStartsAwaitingCheck.insert(id)
        if await subscription.startSession(), let sync {
            await sync.publishRefresh(RefreshTarget(provider: id, half: .subscription))
        }
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

    // MARK: Session reset alert

    /// The reset of the session that has just ended, if one has. Taken before
    /// auto-start, which replaces the window.
    private func endedSession(of provider: ProviderViewModel) -> Date? {
        SessionEnd.ended(previousResetsAt: lastOpenSessionReset[provider.id], current: provider.sessionWindow, now: now())
    }

    /// One alert per ended session; it says so when a newer session is
    /// already open (auto-start opened it, or it was used). Then remembers
    /// the open session's reset, forgetting it once the session is seen closed.
    private func finishSession(of provider: ProviderViewModel, endedAt: Date?) {
        let id = provider.id
        if let endedAt, let alertMonitor {
            let delivers = alertsEnabled && alertKinds.contains(.session) && settings(for: id).alertsEnabled
            let alert = AlertPolicy.sessionAlert(
                displayName: provider.descriptor.displayName,
                endedAt: endedAt,
                sessionIsOpen: provider.sessionIsOpen,
                provider: id
            )
            alertMonitor.deliverOnce(alert, delivers: delivers)
        }

        if let reset = provider.sessionWindow?.resetsAt {
            lastOpenSessionReset[id] = reset
        } else if provider.sessionIsClosed {
            lastOpenSessionReset[id] = nil
        }
    }

    // MARK: Alerts

    var alertSwitches: AlertSwitches {
        AlertSwitches(enabled: alertsEnabled, kinds: AlertKind.allCases.filter(alertKinds.contains).map(\.rawValue))
    }

    func setAlertsEnabled(_ enabled: Bool) {
        alertMonitor?.isEnabled = enabled
        alertsEnabled = alertMonitor?.isEnabled ?? enabled
        sync?.publish(.alerts(alertSwitches))

        if alertsEnabled, !alertKinds.isEmpty {
            alertMonitor?.requestAuthorization()
        }
    }

    func setAlertKind(_ kind: AlertKind, enabled: Bool) {
        alertMonitor?.setEnabled(enabled, for: kind)

        if enabled {
            alertKinds.insert(kind)
        } else {
            alertKinds.remove(kind)
        }
        sync?.publish(.alerts(alertSwitches))

        if enabled, alertsEnabled {
            alertMonitor?.requestAuthorization()
        }
    }

    /// Alerts once when a half starts failing. A failure recorded since
    /// `started` with a cause that counts begins a streak; a success ends it.
    /// A cached older failure is not reported again, and a lost connection
    /// neither alerts nor ends a streak.
    private func trackFailures(of provider: ProviderViewModel, halves: Set<Half>, since started: Date) {
        for model in [provider.subscription, provider.api].compactMap({ $0 }) where halves.contains(model.half) && model.isEnabled {
            let target = RefreshTarget(provider: provider.id, half: model.half)

            guard let failure = model.lastFailure else {
                failingTargets.remove(target)
                continue
            }

            guard failure.date >= started, failure.cause.alertsAsFailure, failingTargets.insert(target).inserted else {
                continue
            }

            let delivers = alertsEnabled && alertKinds.contains(.failures) && settings(for: provider.id).alertsEnabled
            if delivers {
                alertMonitor?.deliver(AlertPolicy.failureAlert(
                    displayName: provider.descriptor.displayName, half: model.half, cause: failure.cause, provider: provider.id
                ))
            }
        }
    }

    /// Checks each enabled, ready half against the alert thresholds. A half
    /// in error or switched off keeps its last report but is not evaluated,
    /// so a stale figure never alerts. Only the given halves are looked at.
    private func evaluateAlerts(for provider: ProviderViewModel, halves: Set<Half> = [.subscription, .api]) {
        guard let alertMonitor else {
            return
        }

        let delivers = alertsEnabled && alertKinds.contains(.usage) && settings(for: provider.id).alertsEnabled

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
        sync?.publish(.provider(id, settings))
        Self.apply(settings, to: provider)
        for half in [Half.subscription, .api] {
            scheduler.setSchedule(Self.interval(settings, half, of: provider), for: RefreshTarget(provider: id, half: half))
        }

        // Turning something on should show data now, not after the next timer tick.
        // The provider coming on brings back each half that is on; otherwise only the half that came on.
        let isOn = Self.enabledFlags(provider)
        forgetSwitchedOff(id, isOn: isOn)
        let halves = [Half.subscription, .api].filter { half in
            wasOn.provider ? !wasOn.isOn(half) && isOn.isOn(half) : isOn.isOn(half)
        }

        if settings.isEnabled, !halves.isEmpty {
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for half in halves {
                        group.addTask { await self.refresh(RefreshTarget(provider: id, half: half), manual: false) }
                    }
                }
            }
        }
    }

    /// A switched-off half starts afresh when it comes back: a session that
    /// ended meanwhile does not alert, and a failure begins a new streak.
    private func forgetSwitchedOff(_ id: Provider, isOn: EnabledFlags) {
        for half in [Half.subscription, .api] where !isOn.provider || !isOn.isOn(half) {
            failingTargets.remove(RefreshTarget(provider: id, half: half))
            if half == .subscription {
                lastOpenSessionReset[id] = nil
            }
        }
    }

    /// The stored settings. A half with no switch in the record starts off
    /// unless it already holds a credential, so a setup from before the
    /// switches keeps working. The old item drew a half its switch hid when
    /// the other half had no credential, so such a half stays shown. Either
    /// way the record is then saved once, so its own keys decide from now on.
    private static func loadSettings(of provider: ProviderViewModel, from store: ProviderSettingsStoring) -> ProviderSettings {
        let loaded = store.loadSettings(for: provider.id)
        guard !loaded.legacyHiddenHalves.isEmpty || !loaded.unsetHalves.isEmpty else {
            return loaded.settings
        }

        var settings = loaded.settings
        for half in loaded.unsetHalves where provider.half(half)?.isConfigured == true {
            settings.setEnabled(true, for: half)
        }
        for half in loaded.legacyHiddenHalves {
            let other: Half = half == .subscription ? .api : .subscription
            if provider.half(other)?.isConfigured != true {
                settings.setShowsInMenuBar(true, for: half)
            }
        }
        store.setSettings(settings, for: provider.id)
        return settings
    }

    private static func apply(_ settings: ProviderSettings, to provider: ProviderViewModel) {
        provider.isEnabled = settings.isEnabled
        provider.subscription?.isEnabled = settings.isSubscriptionEnabled
        provider.api?.isEnabled = settings.isAPIEnabled
    }

    private struct EnabledFlags {
        let provider: Bool
        let subscription: Bool
        let api: Bool

        func isOn(_ half: Half) -> Bool {
            half == .subscription ? subscription : api
        }
    }

    private static func enabledFlags(_ provider: ProviderViewModel) -> EnabledFlags {
        EnabledFlags(
            provider: provider.isEnabled,
            subscription: provider.subscription?.isEnabled ?? false,
            api: provider.api?.isEnabled ?? false
        )
    }

    func setGlobalAppearance(_ appearance: MenuBarAppearance) {
        globalAppearance = appearance
        appearanceStore.setAppearance(appearance)
        sync?.publish(.appearance(appearance))
    }

    /// Switches the provider's custom appearance off so it follows the global one again; the custom one is kept.
    func useDefaultAppearance(for provider: Provider) {
        var settings = settings(for: provider)
        settings.appearanceOverride = nil
        setSettings(settings, for: provider)
    }

    /// The provider's override when it has one, else the global appearance.
    func appearance(for provider: Provider) -> MenuBarAppearance {
        settings(for: provider).appearanceOverride ?? globalAppearance
    }

    /// Which halves of the provider's menu bar item are drawn.
    func menuBarHalves(for provider: Provider) -> MenuBarHalves {
        let settings = settings(for: provider)
        return MenuBarHalves(subscription: settings.showsSubscriptionInMenuBar, api: settings.showsAPIInMenuBar)
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
        sync?.publish(.budget(provider, apiBudgets[provider]))
    }

    // MARK: Menu bar

    /// Enabled providers with an enabled, configured half, in registry
    /// order. When nothing is configured, the first provider's slot alone,
    /// which hosts the app's set-up item, so there is always an item to
    /// click. When everything configured is switched off, nothing: the app
    /// is reached by opening it.
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

    /// Providers with a Settings page, in the order of their menu bar items.
    /// The set-up popover offers the same list.
    var listedProviders: [ProviderViewModel] {
        Self.menuBarDisplayOrder(providers.filter(\.hasAnyHalf))
    }

    /// True while nothing is configured, so the menu bar holds only the
    /// app's set-up item rather than any usage.
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

        // Sparkle shows a "failed to start" alert without a feed, so builds made from source get no updater.
        let build = BuildInfo.main
        let updater: SoftwareUpdating? = build.feedURL != nil ? SparkleUpdater() : nil

        return AppModel(
            providers: providers,
            credentialStore: credentialStore,
            providerSettingsStore: UserDefaultsProviderSettingsStore(),
            appearanceStore: UserDefaultsMenuBarAppearanceStore(),
            budgetStore: UserDefaultsAPIBudgetStore(),
            loginItem: LoginItemModel(manager: LoginItemManager(), store: UserDefaultsLoginItemPreferenceStore()),
            updates: UpdatesModel(updater: updater, build: build),
            sleepObserver: SystemSleepObserver(),
            networkObserver: NetworkReachabilityObserver(),
            alertMonitor: AlertMonitor(notifier: SystemUsageNotifier(), store: UserDefaultsAlertStateStore())
        )
    }
}

import Combine
import Foundation

@MainActor
final class ProviderViewModel: ObservableObject, Identifiable {
    let descriptor: ProviderDescriptor
    let subscription: HalfViewModel?
    let api: HalfViewModel?
    @Published private(set) var isConfigured = false
    /// Off: no menu bar item and no fetching; credentials and the last report are kept.
    @Published var isEnabled = true

    nonisolated var id: Provider { descriptor.id }

    /// False when no half can be fetched yet, so there is nothing to set up.
    var hasAnyHalf: Bool { subscription != nil || api != nil }

    /// At least one enabled half holds a credential, so there is something to show.
    var hasActiveHalf: Bool {
        [subscription, api].contains { $0?.isActive == true }
    }

    /// The provider and its subscription half are switched on, the provider
    /// can start a session, the half is up to date, and the report's short
    /// window is not running. A switched-off half keeps its last report, but
    /// nothing is fetched to show a start worked, so it never reads closed.
    var sessionIsClosed: Bool {
        sessionWindow.map { !$0.isOpen } ?? false
    }

    /// The same up-to-date short window as `sessionIsClosed`, running.
    var sessionIsOpen: Bool {
        sessionWindow?.isOpen ?? false
    }

    /// The short window when a start could be judged from it; see `sessionIsClosed`.
    private var sessionWindow: LimitWindow? {
        guard isEnabled, descriptor.capabilities.canStartSession,
              let shortID = descriptor.shortWindowID,
              let subscription, subscription.isEnabled, subscription.canStartSession, subscription.status == .ready
        else {
            return nil
        }

        return subscription.report?.windows.first { $0.id == shortID }
    }

    /// The subscription half's samples keyed by window id; empty without one.
    func usageHistory(now: Date) -> [String: [UsageSample]] {
        subscription?.usageHistory(now: now) ?? [:]
    }

    func half(_ half: Half) -> HalfViewModel? {
        switch half {
        case .subscription: subscription
        case .api: api
        }
    }

    /// The half's state for the menu bar item; nil when the half is missing or switched off.
    func snapshot(_ half: Half) -> HalfSnapshot? {
        guard let model = self.half(half), model.isEnabled else {
            return nil
        }

        return HalfSnapshot(model)
    }

    private var halfObservers: [AnyCancellable] = []

    init(
        descriptor: ProviderDescriptor,
        subscriptionFetcher: ReportFetching?,
        apiFetcher: ReportFetching?,
        credentialStore: CredentialStoring,
        cache: ReportCaching,
        history: UsageHistoryStoring? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.descriptor = descriptor

        func makeHalf(_ half: Half, fields: [CredentialField], fetcher: ReportFetching?, history: UsageHistoryStoring?) -> HalfViewModel? {
            guard let fetcher else {
                return nil
            }

            return HalfViewModel(
                provider: descriptor.id, half: half, fields: fields, fetcher: fetcher,
                credentialStore: credentialStore, cache: cache, history: history, now: now
            )
        }

        subscription = descriptor.capabilities.hasSubscription
            ? makeHalf(.subscription, fields: descriptor.subscriptionFields, fetcher: subscriptionFetcher, history: history)
            : nil
        api = descriptor.capabilities.hasAPISpend
            ? makeHalf(.api, fields: descriptor.apiFields, fetcher: apiFetcher, history: nil)
            : nil

        recomputeIsConfigured()

        // Forward half changes so views observing the provider update too.
        halfObservers = [subscription, api].compactMap { $0 }.map { half in
            half.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        }
    }

    func refresh(manual: Bool) async {
        async let subscriptionRefresh: Void = refreshHalf(subscription, manual: manual)
        async let apiRefresh: Void = refreshHalf(api, manual: manual)
        _ = await (subscriptionRefresh, apiRefresh)
        recomputeIsConfigured()
    }

    /// Refreshes one half; the other keeps its report and its own timer.
    func refresh(_ half: Half, manual: Bool) async {
        await refreshHalf(self.half(half), manual: manual)
        recomputeIsConfigured()
    }

    func credentialsChanged(half: Half) async {
        switch half {
        case .subscription: await subscription?.credentialsChanged()
        case .api: await api?.credentialsChanged()
        }
        recomputeIsConfigured()
    }

    /// The older of the configured halves' last success; nil if any configured half never succeeded.
    /// A half waiting for an organization choice has nothing to report yet and is left out.
    var updatedAt: Date? {
        let configured = [subscription, api].compactMap { $0 }.filter { $0.isConfigured && $0.status != .needsOrganization }
        let dates = configured.compactMap(\.lastSuccess)
        guard !configured.isEmpty, dates.count == configured.count else {
            return nil
        }

        return dates.min()
    }

    private func refreshHalf(_ half: HalfViewModel?, manual: Bool) async {
        await half?.refresh(manual: manual)
    }

    private func recomputeIsConfigured() {
        isConfigured = (subscription?.isConfigured ?? false) || (api?.isConfigured ?? false)
    }
}

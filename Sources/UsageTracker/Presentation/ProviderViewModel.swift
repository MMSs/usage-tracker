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

    private var halfObservers: [AnyCancellable] = []

    init(
        descriptor: ProviderDescriptor,
        subscriptionFetcher: ReportFetching?,
        apiFetcher: ReportFetching?,
        credentialStore: CredentialStoring,
        cache: ReportCaching,
        now: @escaping () -> Date = Date.init
    ) {
        self.descriptor = descriptor

        func makeHalf(_ half: Half, fields: [CredentialField], fetcher: ReportFetching?) -> HalfViewModel? {
            guard let fetcher else {
                return nil
            }

            return HalfViewModel(
                provider: descriptor.id, half: half, fields: fields, fetcher: fetcher,
                credentialStore: credentialStore, cache: cache, now: now
            )
        }

        subscription = descriptor.capabilities.hasSubscription
            ? makeHalf(.subscription, fields: descriptor.subscriptionFields, fetcher: subscriptionFetcher)
            : nil
        api = descriptor.capabilities.hasAPISpend
            ? makeHalf(.api, fields: descriptor.apiFields, fetcher: apiFetcher)
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

    func credentialsChanged(half: Half) async {
        switch half {
        case .subscription: await subscription?.credentialsChanged()
        case .api: await api?.credentialsChanged()
        }
        recomputeIsConfigured()
    }

    /// The older of the configured halves' last success; nil if any configured half never succeeded.
    var updatedAt: Date? {
        let configured = [subscription, api].compactMap { $0 }.filter(\.isConfigured)
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

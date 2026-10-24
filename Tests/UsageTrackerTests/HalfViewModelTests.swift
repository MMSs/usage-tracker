import Foundation
import Testing
@testable import UsageTracker

func makeReport(_ percent: Double = 10) -> ProviderReport {
    ProviderReport(
        planName: "Pro",
        windows: [LimitWindow(id: "weekly", label: "Weekly", percentUsed: percent, resetsAt: nil, parentID: nil)],
        extras: [],
        spend: nil
    )
}

@Suite @MainActor struct HalfViewModelTests {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let store = MemoryCredentialStore()
    let cache = MemoryReportCache()
    let fetcher = StubReportFetcher(result: .success(makeReport()))
    let key = CredentialKey(provider: .cursor, fieldID: "session-token")

    private var fields: [CredentialField] {
        ProviderRegistry.descriptor(for: .cursor).subscriptionFields
    }

    private func makeModel() -> HalfViewModel {
        let now = now
        return HalfViewModel(
            provider: .cursor, half: .subscription, fields: fields,
            fetcher: fetcher, credentialStore: store, cache: cache, now: { now }
        )
    }

    @Test func noCredentialIsUnconfigured() async {
        let model = makeModel()
        await model.refresh(manual: true)
        #expect(model.status == .unconfigured)
        #expect(!model.isConfigured)
        #expect(fetcher.callCount == 0)
    }

    @Test func successStoresReportAndCache() async {
        store.values[key] = "tok"
        let model = makeModel()
        await model.refresh(manual: true)
        #expect(model.status == .ready)
        #expect(model.report == makeReport())
        #expect(!model.isStale)
        #expect(model.lastSuccess == now)
        #expect(cache.cached(provider: .cursor, half: .subscription) == CachedReport(report: makeReport(), fetchedAt: now))
        #expect(fetcher.lastCredentials == ["session-token": "tok"])
    }

    @Test func blankCredentialIsUnconfigured() async {
        store.values[key] = "   \n"
        let model = makeModel()
        await model.refresh(manual: true)
        #expect(model.status == .unconfigured)
        #expect(fetcher.callCount == 0)
    }

    @Test func unauthorizedBlocksScheduledRefreshes() async {
        store.values[key] = "tok"
        fetcher.result = .failure(.unauthorized)
        let model = makeModel()
        await model.refresh(manual: false)
        #expect(model.status == .expired)
        #expect(model.scheduledRetriesBlocked)
        #expect(fetcher.callCount == 1)

        await model.refresh(manual: false)
        #expect(fetcher.callCount == 1)

        await model.refresh(manual: true)
        #expect(fetcher.callCount == 2)
    }

    @Test func errorKeepsLastReport() async {
        store.values[key] = "tok"
        let model = makeModel()
        await model.refresh(manual: true)
        fetcher.result = .failure(.transport)
        await model.refresh(manual: true)
        #expect(model.status == .error)
        #expect(model.report == makeReport())
        #expect(model.lastSuccess == now)
        #expect(!model.scheduledRetriesBlocked)
    }

    @Test func challengeIsAnErrorAndKeepsReport() async {
        store.values[key] = "tok"
        let model = makeModel()
        await model.refresh(manual: true)
        fetcher.result = .failure(.challenge)
        await model.refresh(manual: true)
        #expect(model.status == .error)
        #expect(model.report == makeReport())
    }

    @Test func cachedReportLoadsStaleOnInit() {
        store.values[key] = "tok"
        let fetchedAt = now.addingTimeInterval(-60)
        cache.store(CachedReport(report: makeReport(42), fetchedAt: fetchedAt), provider: .cursor, half: .subscription)
        let model = makeModel()
        #expect(model.report == makeReport(42))
        #expect(model.lastSuccess == fetchedAt)
        #expect(model.isStale)
        #expect(model.status == .loading)
    }

    @Test func credentialWithoutCacheStartsLoading() {
        store.values[key] = "tok"
        let model = makeModel()
        #expect(model.status == .loading)
        #expect(model.report == nil)
    }

    @Test func noCredentialAtInitIsUnconfigured() {
        let model = makeModel()
        #expect(model.status == .unconfigured)
    }

    @Test func throwingStoreAtInitIsAnError() {
        store.readError = FetchError.transport
        let model = makeModel()
        #expect(model.status == .error)
    }

    @Test func cachedReportStaysVisibleWhileRefreshing() async {
        store.values[key] = "tok"
        cache.store(CachedReport(report: makeReport(42), fetchedAt: now), provider: .cursor, half: .subscription)
        let gate = SuspendedGate()
        fetcher.gate = gate
        let model = makeModel()
        let task = Task { await model.refresh(manual: true) }
        await settle()
        #expect(model.status == .loading)
        #expect(model.report == makeReport(42))
        gate.resume()
        await task.value
        #expect(model.status == .ready)
        #expect(model.report == makeReport())
    }

    @Test func throwingStoreIsAnErrorNotUnconfigured() async {
        store.values[key] = "tok"
        let model = makeModel()
        await model.refresh(manual: true)
        store.readError = FetchError.transport
        await model.refresh(manual: true)
        #expect(model.status == .error)
        #expect(model.report == makeReport())
        #expect(store.removedKeys.isEmpty)
        #expect(cache.clearCount == 0)
        #expect(cache.cached(provider: .cursor, half: .subscription) != nil)
    }

    @Test func credentialRemovedMidFlightDiscardsResponse() async {
        store.values[key] = "tok"
        let gate = SuspendedGate()
        fetcher.gate = gate
        let model = makeModel()
        let task = Task { await model.refresh(manual: true) }
        await settle()
        #expect(fetcher.callCount == 1)

        store.values[key] = nil
        await model.credentialsChanged()
        gate.resume()
        await task.value

        #expect(model.status == .unconfigured)
        #expect(model.report == nil)
        #expect(model.lastSuccess == nil)
        #expect(cache.cached(provider: .cursor, half: .subscription) == nil)
    }

    @Test func removingCredentialClearsReportAndCache() async {
        store.values[key] = "tok"
        let model = makeModel()
        await model.refresh(manual: true)
        store.values[key] = nil
        await model.credentialsChanged()
        #expect(model.status == .unconfigured)
        #expect(model.report == nil)
        #expect(model.lastSuccess == nil)
        #expect(cache.cached(provider: .cursor, half: .subscription) == nil)
    }

    @Test func credentialsChangedClearsBlockAndRefreshes() async {
        store.values[key] = "old"
        fetcher.result = .failure(.unauthorized)
        let model = makeModel()
        await model.refresh(manual: true)
        #expect(model.status == .expired)

        store.values[key] = "new"
        fetcher.result = .success(makeReport())
        await model.credentialsChanged()
        #expect(model.status == .ready)
        #expect(!model.scheduledRetriesBlocked)
        #expect(fetcher.lastCredentials == ["session-token": "new"])
        #expect(fetcher.callCount == 2)
    }

    @Test func budgetFieldIsNotACredential() async {
        let descriptor = ProviderRegistry.descriptor(for: .anthropic)
        let apiStore = store
        apiStore.values[CredentialKey(provider: .anthropic, fieldID: "admin-key")] = "adm"
        let apiFetcher = StubReportFetcher(result: .success(makeReport()))
        let model = HalfViewModel(
            provider: .anthropic, half: .api, fields: descriptor.apiFields,
            fetcher: apiFetcher, credentialStore: apiStore, cache: cache, now: { [now] in now }
        )
        await model.refresh(manual: true)
        #expect(model.status == .ready)
        #expect(apiFetcher.lastCredentials == ["admin-key": "adm"])
    }
}

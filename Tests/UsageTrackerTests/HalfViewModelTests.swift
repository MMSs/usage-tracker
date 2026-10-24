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
        cache.store(CachedReport(report: makeReport(), fetchedAt: now), provider: .cursor, half: .subscription)
        let model = makeModel()
        await model.refresh(manual: true)
        #expect(model.status == .unconfigured)
        #expect(!model.isConfigured)
        #expect(fetcher.callCount == 0)
        #expect(cache.cached(provider: .cursor, half: .subscription) == nil)
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

    @Test func successfulManualRetryClearsTheBlock() async {
        store.values[key] = "tok"
        fetcher.result = .failure(.unauthorized)
        let model = makeModel()
        await model.refresh(manual: true)
        #expect(model.status == .expired)

        fetcher.result = .success(makeReport())
        await model.refresh(manual: true)
        #expect(model.status == .ready)
        #expect(!model.scheduledRetriesBlocked)

        await model.refresh(manual: false)
        #expect(fetcher.callCount == 3)
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

    @Test func cancelledFetchLeavesStateUnchanged() async {
        store.values[key] = "tok"
        let model = makeModel()
        await model.refresh(manual: true)
        fetcher.thrownError = CancellationError()
        await model.refresh(manual: true)
        #expect(model.status == .ready)
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

    @Test func throwingStoreAtInitIsAnErrorButKeepsCachedReport() {
        cache.store(CachedReport(report: makeReport(42), fetchedAt: now), provider: .cursor, half: .subscription)
        store.readError = FetchError.transport
        let model = makeModel()
        #expect(model.status == .error)
        #expect(model.report == makeReport(42))
        #expect(model.lastSuccess == now)
        #expect(model.isStale)
        #expect(store.removedKeys.isEmpty)
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

@Suite @MainActor struct HalfViewModelFailureTests {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let store = MemoryCredentialStore()
    let cache = MemoryReportCache()
    let fetcher = StubReportFetcher(result: .success(makeReport()))
    let key = CredentialKey(provider: .cursor, fieldID: "session-token")

    private func makeModel() -> HalfViewModel {
        let now = now
        return HalfViewModel(
            provider: .cursor, half: .subscription,
            fields: ProviderRegistry.descriptor(for: .cursor).subscriptionFields,
            fetcher: fetcher, credentialStore: store, cache: cache, now: { now }
        )
    }

    @Test(arguments: [
        (FetchError.transport, RefreshFailure.transport),
        (.challenge, .challenge),
        (.httpStatus(429), .httpStatus(429)),
        (.decoding, .decoding),
        (.invalidResponse, .decoding),
        (.unauthorized, .unauthorized),
        (.rateLimited(until: Date(timeIntervalSince1970: 1_000_120)), .rateLimited(until: Date(timeIntervalSince1970: 1_000_120))),
        (.rateLimited(until: nil), .rateLimited(until: nil)),
        (.needsOrganizationChoice, .needsOrganization),
    ])
    func fetchErrorsMapToACause(error: FetchError, cause: RefreshFailure) {
        #expect(RefreshFailure(error) == cause)
    }

    @Test func otherErrorsAreUnexpected() {
        struct Odd: Error {}
        #expect(RefreshFailure(Odd()) == .unexpected)
    }

    @Test func failureRecordsTheCauseAndTime() async {
        store.values[key] = "tok"
        fetcher.result = .failure(.httpStatus(500))
        let model = makeModel()
        await model.refresh(manual: true)
        #expect(model.status == .error)
        #expect(model.lastFailure == RecordedFailure(cause: .httpStatus(500), date: now))
    }

    @Test func expiredRecordsUnauthorized() async {
        store.values[key] = "tok"
        fetcher.result = .failure(.unauthorized)
        let model = makeModel()
        await model.refresh(manual: false)
        #expect(model.status == .expired)
        #expect(model.lastFailure?.cause == .unauthorized)
    }

    @Test func unexpectedErrorIsRecorded() async {
        struct Odd: Error {}
        store.values[key] = "tok"
        fetcher.thrownError = Odd()
        let model = makeModel()
        await model.refresh(manual: true)
        #expect(model.status == .error)
        #expect(model.lastFailure?.cause == .unexpected)
    }

    @Test func successClearsTheFailure() async {
        store.values[key] = "tok"
        fetcher.result = .failure(.transport)
        let model = makeModel()
        await model.refresh(manual: true)
        #expect(model.lastFailure?.cause == .transport)

        fetcher.result = .success(makeReport())
        await model.refresh(manual: true)
        #expect(model.status == .ready)
        #expect(model.lastFailure == nil)
    }

    @Test func rateLimitedKeepsTheReportAndSkipsScheduledRefreshesUntilRetryAfter() async {
        final class Clock { var now = Date(timeIntervalSince1970: 1_000_000) }
        let clock = Clock()
        store.values[key] = "tok"
        let model = HalfViewModel(
            provider: .cursor, half: .subscription,
            fields: ProviderRegistry.descriptor(for: .cursor).subscriptionFields,
            fetcher: fetcher, credentialStore: store, cache: cache, now: { clock.now }
        )
        await model.refresh(manual: false)
        let until = clock.now.addingTimeInterval(300)
        fetcher.result = .failure(.rateLimited(until: until))
        await model.refresh(manual: false)
        #expect(model.status == .error)
        #expect(model.report == makeReport())
        #expect(model.lastFailure?.cause == .rateLimited(until: until))
        #expect(fetcher.callCount == 2)

        clock.now = until.addingTimeInterval(-1)
        await model.refresh(manual: false)
        #expect(fetcher.callCount == 2)
        #expect(model.status == .error)

        // The owner can still ask now.
        await model.refresh(manual: true)
        #expect(fetcher.callCount == 3)

        clock.now = until
        fetcher.result = .success(makeReport(20))
        await model.refresh(manual: false)
        #expect(fetcher.callCount == 4)
        #expect(model.status == .ready)
        #expect(model.lastFailure == nil)
    }

    /// Only a success or a newer 429 ends the wait: a manual refresh that
    /// fails another way meanwhile has not told the app the limit lifted.
    @Test func rateLimitedWaitOutlastsAnotherFailureAndANewer429ReplacesIt() async {
        final class Clock { var now = Date(timeIntervalSince1970: 1_000_000) }
        let clock = Clock()
        store.values[key] = "tok"
        let model = HalfViewModel(
            provider: .cursor, half: .subscription,
            fields: ProviderRegistry.descriptor(for: .cursor).subscriptionFields,
            fetcher: fetcher, credentialStore: store, cache: cache, now: { clock.now }
        )
        let until = clock.now.addingTimeInterval(300)
        fetcher.result = .failure(.rateLimited(until: until))
        await model.refresh(manual: false)
        #expect(model.rateLimitedUntil == until)

        fetcher.result = .failure(.transport)
        await model.refresh(manual: true)
        #expect(model.lastFailure?.cause == .transport)
        #expect(model.rateLimitedUntil == until)

        clock.now = until.addingTimeInterval(-1)
        await model.refresh(manual: false)
        #expect(fetcher.callCount == 2)

        fetcher.result = .failure(.rateLimited(until: nil))
        await model.refresh(manual: true)
        #expect(model.rateLimitedUntil == nil)
        await model.refresh(manual: false)
        #expect(fetcher.callCount == 4)

        fetcher.result = .failure(.rateLimited(until: clock.now.addingTimeInterval(60)))
        await model.refresh(manual: false)
        fetcher.result = .success(makeReport())
        await model.refresh(manual: true)
        #expect(model.rateLimitedUntil == nil)
        #expect(fetcher.callCount == 6)
    }

    @Test func rateLimitedWithoutRetryAfterKeepsTheSchedule() async {
        store.values[key] = "tok"
        fetcher.result = .failure(.rateLimited(until: nil))
        let model = makeModel()
        await model.refresh(manual: false)
        await model.refresh(manual: false)
        #expect(fetcher.callCount == 2)
        #expect(model.status == .error)
    }

    @Test func keychainFailureAtInitIsRecorded() {
        store.values[key] = "tok"
        store.readError = FetchError.transport
        let model = makeModel()
        #expect(model.status == .error)
        #expect(model.lastFailure == RecordedFailure(cause: .keychain, date: now))
    }

    @Test func keychainFailureOnRefreshIsRecorded() async {
        store.values[key] = "tok"
        let model = makeModel()
        await model.refresh(manual: true)
        store.readError = FetchError.transport
        await model.refresh(manual: true)
        #expect(model.status == .error)
        #expect(model.lastFailure?.cause == .keychain)
        #expect(fetcher.callCount == 1)
    }

    @Test func removingTheCredentialClearsTheFailure() async {
        store.values[key] = "tok"
        fetcher.result = .failure(.transport)
        let model = makeModel()
        await model.refresh(manual: true)
        store.values[key] = nil
        await model.credentialsChanged()
        #expect(model.status == .unconfigured)
        #expect(model.lastFailure == nil)
    }

    /// A refresh cancelled by sleep or going offline used to leave a half
    /// with no report on "Loading…", hiding the error it had before.
    @Test func cancelledRetryKeepsThePreviousErrorVisible() async {
        store.values[key] = "tok"
        fetcher.result = .failure(.challenge)
        let model = makeModel()
        await model.refresh(manual: false)
        #expect(model.status == .error)
        #expect(model.report == nil)

        let gate = SuspendedGate()
        fetcher.gate = gate
        fetcher.thrownError = CancellationError()
        let task = Task { await model.refresh(manual: false) }
        await settle()
        #expect(model.status == .loading)
        gate.resume()
        await task.value

        #expect(model.status == .error)
        #expect(model.lastFailure?.cause == .challenge)
    }

    /// A manual refresh from the popover overlapping a scheduled one: the
    /// older result is dropped as superseded, then sleep cancels the newer
    /// one. The newer one began on the older one's "Loading…", so restoring
    /// the status it started from left the half loading with its error hidden.
    @Test(arguments: [
        (true, FetchError.challenge, HalfStatus.error),
        (false, .challenge, .error),
        (true, .unauthorized, .expired),
    ])
    func overlappingRefreshCancelledAfterTheOlderWasSupersededShowsTheLastFailure(
        olderSucceeds: Bool,
        earlier: FetchError,
        expected: HalfStatus
    ) async {
        store.values[key] = "tok"
        fetcher.result = .failure(earlier)
        let model = makeModel()
        await model.refresh(manual: true)
        #expect(model.report == nil)

        let olderGate = SuspendedGate()
        let newerGate = SuspendedGate()
        let older: Result<ProviderReport, any Error> = olderSucceeds ? .success(makeReport()) : .failure(FetchError.transport)
        fetcher.script = [(olderGate, older), (newerGate, .failure(CancellationError()))]
        let olderTask = Task { await model.refresh(manual: true) }
        await settle()
        // Scheduled refreshes are skipped once expired, so that overlap is two manual ones.
        let newerTask = Task { await model.refresh(manual: earlier == .unauthorized) }
        await settle()
        #expect(fetcher.callCount == 3)
        #expect(model.status == .loading)

        olderGate.resume()
        await olderTask.value
        newerGate.resume()
        await newerTask.value

        #expect(model.status == expected)
        #expect(model.report == nil)
        #expect(model.lastFailure?.cause == RefreshFailure(earlier))
    }

    @Test func cancelledRetryKeepsExpiredVisible() async {
        store.values[key] = "tok"
        fetcher.result = .failure(.unauthorized)
        let model = makeModel()
        await model.refresh(manual: true)

        fetcher.thrownError = CancellationError()
        await model.refresh(manual: true)

        #expect(model.status == .expired)
        #expect(model.scheduledRetriesBlocked)
    }
}

/// Lists `listing` on every fetch and, like the Anthropic service, needs a
/// choice when it lists several organizations and none is chosen.
@MainActor
final class StubOrganizationScopedFetcher: ReportFetching, OrganizationScopedFetching {
    var listing: [AccountOrganization] = []
    private(set) var organizations: [AccountOrganization] = []
    private(set) var selectedOrganizationID: String?
    private(set) var callCount = 0
    private(set) var resetCount = 0

    func fetchReport(credentials: [String: String], today: Date) async throws -> ProviderReport {
        callCount += 1
        organizations = listing
        let chosen = listing.contains { $0.id == selectedOrganizationID }
        guard chosen || listing.count == 1 else {
            throw FetchError.needsOrganizationChoice
        }
        return makeReport()
    }

    func selectOrganization(_ id: String) {
        selectedOrganizationID = id
    }

    func resetOrganizations() {
        resetCount += 1
        selectedOrganizationID = nil
        organizations = []
    }
}

@Suite @MainActor struct HalfViewModelOrganizationTests {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let store = MemoryCredentialStore()
    let cache = MemoryReportCache()
    let fetcher = StubOrganizationScopedFetcher()
    let key = CredentialKey(provider: .anthropic, fieldID: "session-key")
    let two = [AccountOrganization(id: "org-a", name: "Personal"), AccountOrganization(id: "org-b", name: "Team")]

    private func makeModel() -> HalfViewModel {
        let now = now
        return HalfViewModel(
            provider: .anthropic, half: .subscription,
            fields: ProviderRegistry.descriptor(for: .anthropic).subscriptionFields,
            fetcher: fetcher, credentialStore: store, cache: cache, now: { now }
        )
    }

    @Test func severalOrganizationsAndNoChoiceWaitForOneWithoutScheduledRefreshes() async {
        store.values[key] = "sk"
        fetcher.listing = two
        let model = makeModel()

        await model.refresh(manual: false)
        #expect(model.status == .needsOrganization)
        #expect(model.lastFailure?.cause == .needsOrganization)
        #expect(model.organizations == two)
        #expect(model.chosenOrganization == nil)
        #expect(model.scheduledRetriesBlocked)

        await model.refresh(manual: false)
        #expect(fetcher.callCount == 1)

        // A manual refresh still asks, in case the account's organizations changed.
        await model.refresh(manual: true)
        #expect(fetcher.callCount == 2)
        #expect(model.status == .needsOrganization)
    }

    @Test func choosingAnOrganizationStoresItAndRefreshesNow() async {
        store.values[key] = "sk"
        fetcher.listing = two
        let model = makeModel()
        await model.refresh(manual: false)

        await model.selectOrganization("org-b")

        #expect(fetcher.selectedOrganizationID == "org-b")
        #expect(fetcher.callCount == 2)
        #expect(model.status == .ready)
        #expect(model.chosenOrganization == two[1])
        #expect(model.lastFailure == nil)
        #expect(!model.scheduledRetriesBlocked)
    }

    @Test func aChoiceNoLongerListedIsNotChosen() async {
        store.values[key] = "sk"
        fetcher.listing = two
        let model = makeModel()
        await model.selectOrganization("org-b")
        #expect(model.chosenOrganization == two[1])

        fetcher.listing = [two[0], AccountOrganization(id: "org-c", name: nil)]
        await model.refresh(manual: true)

        #expect(model.status == .needsOrganization)
        #expect(model.chosenOrganization == nil)
    }

    @Test func aLoneOrganizationIsUsedWithoutAChoice() async {
        store.values[key] = "sk"
        fetcher.listing = [two[0]]
        let model = makeModel()

        await model.refresh(manual: false)

        #expect(model.status == .ready)
        #expect(model.organizations == [two[0]])
        #expect(fetcher.selectedOrganizationID == nil)
    }

    @Test(arguments: [true, false])
    func replacingOrRemovingTheCredentialForgetsTheChoice(replaced: Bool) async {
        store.values[key] = "sk"
        fetcher.listing = two
        let model = makeModel()
        await model.selectOrganization("org-a")

        store.values[key] = replaced ? "sk-other" : nil
        await model.credentialsChanged()

        #expect(fetcher.resetCount == 1)
        #expect(fetcher.selectedOrganizationID == nil)
        #expect(model.status == (replaced ? .needsOrganization : .unconfigured))
        #expect(model.organizations == (replaced ? two : []))
    }

    @Test func noCredentialAtLaunchForgetsAnyStoredChoice() {
        _ = makeModel()
        #expect(fetcher.resetCount == 1)
    }

    @Test func aFetcherWithoutOrganizationsHasNone() async {
        store.values[CredentialKey(provider: .cursor, fieldID: "session-token")] = "tok"
        let model = HalfViewModel(
            provider: .cursor, half: .subscription,
            fields: ProviderRegistry.descriptor(for: .cursor).subscriptionFields,
            fetcher: StubReportFetcher(result: .success(makeReport())), credentialStore: store, cache: cache
        )

        await model.refresh(manual: true)
        await model.selectOrganization("org-a")

        #expect(model.organizations.isEmpty)
        #expect(model.status == .ready)
    }
}

import Foundation
import Testing
@testable import UsageTracker

@Suite @MainActor struct ProviderViewModelTests {
    let t1 = Date(timeIntervalSince1970: 1_000_000)
    let t2 = Date(timeIntervalSince1970: 2_000_000)
    let store = MemoryCredentialStore()
    let cache = MemoryReportCache()
    let subFetcher = StubReportFetcher(result: .success(makeReport(1)))
    let apiFetcher = StubReportFetcher(result: .success(makeReport(2)))

    private func makeModel(_ provider: Provider, now: @escaping () -> Date) -> ProviderViewModel {
        let descriptor = ProviderRegistry.descriptor(for: provider)
        return ProviderViewModel(
            descriptor: descriptor,
            subscriptionFetcher: descriptor.capabilities.hasSubscription ? subFetcher : nil,
            apiFetcher: descriptor.capabilities.hasAPISpend ? apiFetcher : nil,
            credentialStore: store, cache: cache, now: now
        )
    }

    @Test func halvesFollowCapabilities() {
        let cursor = makeModel(.cursor, now: { t1 })
        #expect(cursor.subscription != nil)
        #expect(cursor.api == nil)
        #expect(cursor.id == .cursor)

        let anthropic = makeModel(.anthropic, now: { t1 })
        #expect(anthropic.subscription != nil)
        #expect(anthropic.api != nil)
    }

    @Test func hasAnyHalfOnlyWithAFetcher() {
        #expect(makeModel(.cursor, now: { t1 }).hasAnyHalf)

        let unfetched = ProviderViewModel(
            descriptor: ProviderRegistry.descriptor(for: .anthropic),
            subscriptionFetcher: nil, apiFetcher: nil,
            credentialStore: store, cache: cache
        )
        #expect(!unfetched.hasAnyHalf)
    }

    /// A half the menu bar marks as failed must also get a popover section
    /// (drawn for active halves only) with an explanation in it.
    @Test func aFailedHalfWithNoReportIsDrawnAndExplained() async throws {
        store.values[CredentialKey(provider: .anthropic, fieldID: "admin-key")] = "adm"
        apiFetcher.result = .failure(.transport)
        let model = makeModel(.anthropic, now: { t1 })
        await model.refresh(manual: false)

        let item = try #require(MenuBarItemBuilder.make(
            descriptor: model.descriptor, subscription: model.snapshot(.subscription), api: model.snapshot(.api),
            apiBudget: nil, now: t1
        ))
        #expect(item.api == .status(.error))
        #expect(model.isConfigured)
        let api = try #require(model.api)
        #expect(api.isActive)
        #expect(api.report == nil)
        #expect(PopoverPresentation.halfError(api, descriptor: model.descriptor, display: item.api)?.text
            == "API spend: Couldn't reach api.anthropic.com.")

        api.isEnabled = false
        #expect(model.snapshot(.api) == nil)
        #expect(!api.isActive)
    }

    @Test func aFailedHalfWithACachedReportIsExplained() async throws {
        store.values[CredentialKey(provider: .cursor, fieldID: "session-token")] = "tok"
        let model = makeModel(.cursor, now: { t1 })
        await model.refresh(manual: false)
        subFetcher.result = .failure(.httpStatus(502))
        await model.refresh(manual: false)

        let half = try #require(model.subscription)
        #expect(half.report != nil)
        #expect(PopoverPresentation.halfError(half, descriptor: model.descriptor, display: nil)?.text
            == "Plan usage: Cursor returned an error (HTTP 502).")
    }

    @Test func settingsStatusHasALinePerFailingHalf() async {
        store.values[CredentialKey(provider: .anthropic, fieldID: "session-key")] = "sk"
        store.values[CredentialKey(provider: .anthropic, fieldID: "admin-key")] = "adm"
        subFetcher.result = .failure(.challenge)
        apiFetcher.result = .failure(.httpStatus(503))
        let model = makeModel(.anthropic, now: { t1 })
        await model.refresh(manual: false)

        #expect(ProviderStatus.make(for: model, item: nil).lines == [
            .init(text: "Plan usage: claude.ai asked for a browser check. Open claude.ai in your browser, then Refresh.", tone: .warning),
            .init(text: "API spend: Anthropic API returned an error (HTTP 503). It retries automatically.", tone: .warning),
        ])

        model.api?.isEnabled = false
        #expect(ProviderStatus.make(for: model, item: nil).lines.count == 1)
    }

    @Test func aProviderWithBothFetchersHasTwoHalves() {
        let model = makeModel(.anthropic, now: { t1 })
        #expect(model.hasAnyHalf)
        #expect([model.subscription, model.api].compactMap { $0 }.count == 2)
    }

    @Test func isConfiguredWhenAnyHalfIs() async {
        store.values[CredentialKey(provider: .anthropic, fieldID: "admin-key")] = "adm"
        let model = makeModel(.anthropic, now: { t1 })
        #expect(model.isConfigured)
        await model.refresh(manual: true)
        #expect(model.isConfigured)
        #expect(model.subscription?.status == .unconfigured)
        #expect(model.api?.status == .ready)
    }

    @Test func notConfiguredWithoutCredentials() async {
        let model = makeModel(.anthropic, now: { t1 })
        await model.refresh(manual: true)
        #expect(!model.isConfigured)
        #expect(model.updatedAt == nil)
    }

    @Test func oneHalfFailingDoesNotStopTheOther() async {
        store.values[CredentialKey(provider: .anthropic, fieldID: "session-key")] = "sk"
        store.values[CredentialKey(provider: .anthropic, fieldID: "admin-key")] = "adm"
        subFetcher.result = .failure(.transport)
        let model = makeModel(.anthropic, now: { t1 })
        await model.refresh(manual: true)
        #expect(model.subscription?.status == .error)
        #expect(model.api?.status == .ready)
    }

    @Test func updatedAtIsTheOlderSuccess() async {
        store.values[CredentialKey(provider: .anthropic, fieldID: "session-key")] = "sk"
        store.values[CredentialKey(provider: .anthropic, fieldID: "admin-key")] = "adm"
        var clock = t1
        let model = makeModel(.anthropic, now: { clock })
        #expect(model.updatedAt == nil)

        await model.subscription?.refresh(manual: true)
        #expect(model.updatedAt == nil)

        clock = t2
        await model.api?.refresh(manual: true)
        #expect(model.updatedAt == t1)
    }

    /// The half waiting for an organization choice dropped its kept report, so
    /// its old time must not stand in for "Updated".
    @Test func updatedAtIgnoresAHalfWaitingForAnOrganization() async {
        store.values[CredentialKey(provider: .anthropic, fieldID: "session-key")] = "sk"
        store.values[CredentialKey(provider: .anthropic, fieldID: "admin-key")] = "adm"
        cache.store(CachedReport(report: makeReport(), fetchedAt: t1), provider: .anthropic, half: .subscription)
        let organizations = StubOrganizationScopedFetcher()
        organizations.listing = [AccountOrganization(id: "a", name: "Personal"), AccountOrganization(id: "b", name: "Team")]
        let model = ProviderViewModel(
            descriptor: ProviderRegistry.descriptor(for: .anthropic),
            subscriptionFetcher: organizations, apiFetcher: apiFetcher,
            credentialStore: store, cache: cache, now: { t2 }
        )
        #expect(model.updatedAt == nil)

        await model.refresh(manual: true)
        #expect(model.subscription?.status == .needsOrganization)
        #expect(model.api?.status == .ready)
        #expect(model.updatedAt == t2)

        await model.subscription?.selectOrganization("b")
        #expect(model.updatedAt == t2)
    }

    @Test func credentialsChangedRefreshesOnlyThatHalfAndUpdatesConfigured() async {
        let model = makeModel(.anthropic, now: { t1 })
        #expect(!model.isConfigured)
        store.values[CredentialKey(provider: .anthropic, fieldID: "admin-key")] = "adm"
        await model.credentialsChanged(half: .api)
        #expect(model.isConfigured)
        #expect(model.api?.status == .ready)
        #expect(subFetcher.callCount == 0)

        store.values[CredentialKey(provider: .anthropic, fieldID: "admin-key")] = nil
        await model.credentialsChanged(half: .api)
        #expect(!model.isConfigured)
    }
}

@Suite @MainActor struct SessionIsClosedTests {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let store = MemoryCredentialStore()
    let cache = MemoryReportCache()
    let subFetcher = StubSessionFetcher(fetchResult: .success(makeReport()))

    private func sessionReport(resetsAt: Date?, id: String = "session") -> ProviderReport {
        ProviderReport(
            planName: "Pro",
            windows: [LimitWindow(id: id, label: "Session", percentUsed: 0, resetsAt: resetsAt, parentID: nil)],
            extras: [], spend: nil
        )
    }

    private func makeModel(_ provider: Provider = .anthropic) -> ProviderViewModel {
        let now = now
        return ProviderViewModel(
            descriptor: ProviderRegistry.descriptor(for: provider),
            subscriptionFetcher: subFetcher, apiFetcher: nil,
            credentialStore: store, cache: cache, now: { now }
        )
    }

    private func refreshed(_ report: ProviderReport) async -> ProviderViewModel {
        store.values[CredentialKey(provider: .anthropic, fieldID: "session-key")] = "sk"
        subFetcher.fetchResult = .success(report)
        let model = makeModel()
        await model.refresh(manual: true)
        return model
    }

    @Test func sessionIsClosedOnlyWhenReadyAndTheSessionHasNoReset() async {
        let closed = await refreshed(sessionReport(resetsAt: nil))
        #expect(closed.sessionIsClosed)

        let open = await refreshed(sessionReport(resetsAt: now.addingTimeInterval(3600)))
        #expect(!open.sessionIsClosed)

        let missing = await refreshed(sessionReport(resetsAt: nil, id: "weekly"))
        #expect(!missing.sessionIsClosed)

        store.values[CredentialKey(provider: .anthropic, fieldID: "session-key")] = "sk"
        subFetcher.fetchResult = .failure(.transport)
        let failed = makeModel()
        await failed.refresh(manual: true)
        #expect(failed.subscription?.status == .error)
        #expect(!failed.sessionIsClosed)
    }

    @Test func aProviderThatCannotStartIsNeverClosed() async {
        store.values[CredentialKey(provider: .cursor, fieldID: "session-token")] = "tok"
        subFetcher.fetchResult = .success(sessionReport(resetsAt: nil))
        let model = makeModel(.cursor)
        await model.refresh(manual: true)
        #expect(!model.sessionIsClosed)
    }
}

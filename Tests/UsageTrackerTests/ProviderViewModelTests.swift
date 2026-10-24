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

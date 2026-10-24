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

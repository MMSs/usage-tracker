import Foundation
import Testing
@testable import UsageTracker

final class MemorySyncPreferencesStore: SyncPreferencesStoring {
    var mode: SyncMode
    let deviceID: String

    init(mode: SyncMode, deviceID: String) {
        self.mode = mode
        self.deviceID = deviceID
    }
}

/// A clock several Macs share, moved by hand.
final class TestClock: @unchecked Sendable {
    var date = Date(timeIntervalSince1970: 1_800_000_000)

    func advance(_ seconds: TimeInterval) {
        date = date.addingTimeInterval(seconds)
    }
}

/// One simulated Mac: its own app model, stores and fetcher, on a shared iCloud.
@MainActor
struct SimulatedMac {
    let model: AppModel
    let sync: SyncCoordinator
    let transport: InMemorySyncTransport
    let fetcher: StubReportFetcher
    let history: MemoryUsageHistoryStore
    let local: MemoryCredentialStore

    static let cursorToken = CredentialKey(provider: .cursor, fieldID: "session-token")

    init(
        _ deviceID: String,
        server: InMemorySyncServer,
        sharedKeychain: MemoryCredentialStore,
        clock: TestClock,
        mode: SyncMode = .everything,
        report: ProviderReport = makeReport(1)
    ) {
        let now = { clock.date }
        local = MemoryCredentialStore()
        let credentials = SyncingCredentialStore(local: local, shared: sharedKeychain)
        transport = InMemorySyncTransport(server: server)
        sync = SyncCoordinator(
            transport: transport,
            credentials: credentials,
            preferences: MemorySyncPreferencesStore(mode: mode, deviceID: deviceID),
            credentialKeys: [Self.cursorToken],
            now: now
        )
        fetcher = StubReportFetcher(result: .success(report))
        history = MemoryUsageHistoryStore()

        let cursor = ProviderViewModel(
            descriptor: ProviderRegistry.descriptor(for: .cursor),
            subscriptionFetcher: fetcher,
            apiFetcher: nil,
            credentialStore: credentials,
            cache: MemoryReportCache(),
            history: history,
            now: now
        )
        let others = ProviderRegistry.all.dropFirst().map { descriptor in
            ProviderViewModel(descriptor: descriptor, subscriptionFetcher: nil, apiFetcher: nil, credentialStore: credentials, cache: MemoryReportCache())
        }

        model = AppModel(
            providers: [cursor] + others,
            credentialStore: credentials,
            providerSettingsStore: MemoryProviderSettingsStore([.cursor: ProviderSettings()]),
            appearanceStore: MemoryMenuBarAppearanceStore(),
            budgetStore: MemoryAPIBudgetStore(),
            loginItem: .stub(),
            sleepObserver: ControllableSleepObserver(),
            networkObserver: ControllableNetworkObserver(),
            sleep: { _ in },
            now: now,
            sync: sync
        )
    }

    var cursor: HalfViewModel { model.provider(.cursor).subscription! }

    func scheduledRefresh() async {
        await model.refresh(RefreshTarget(provider: .cursor, half: .subscription), manual: false)
    }
}

@Suite @MainActor struct SyncTests {
    let server = InMemorySyncServer()
    let keychain = MemoryCredentialStore()
    let clock = TestClock()
    let cursor = RefreshTarget(provider: .cursor, half: .subscription)

    init() {
        keychain.values[SimulatedMac.cursorToken] = "tok"
    }

    private func mac(_ id: String, mode: SyncMode = .everything, report: ProviderReport = makeReport(1)) async -> SimulatedMac {
        let mac = SimulatedMac(id, server: server, sharedKeychain: keychain, clock: clock, mode: mode, report: report)
        await mac.sync.start()
        return mac
    }

    // MARK: Fetch turns

    @Test func oneMacFetchesAndTheOtherAdoptsItsAnswer() async {
        let first = await mac("A", report: makeReport(42))
        let second = await mac("B")

        await first.scheduledRefresh()
        clock.advance(60)
        await second.scheduledRefresh()

        #expect(first.fetcher.callCount == 1)
        #expect(second.fetcher.callCount == 0)
        #expect(second.cursor.report == makeReport(42))
        #expect(second.cursor.status == .ready)
    }

    @Test func anAnswerOlderThanTheIntervalIsFetchedAgain() async {
        let first = await mac("A")
        let second = await mac("B")

        await first.scheduledRefresh()
        clock.advance(TimeInterval(RefreshInterval.default.seconds))
        await second.scheduledRefresh()

        #expect(second.fetcher.callCount == 1)
    }

    @Test func aMacFetchingNowHoldsTheTurn() async throws {
        let second = await mac("B")
        let lease = FetchLease(device: "A", expiresAt: clock.date.addingTimeInterval(30))
        _ = server.put(SyncRecordName.lease(cursor), payload: try SyncCoding.encode(lease))

        await second.scheduledRefresh()

        #expect(second.fetcher.callCount == 0)
    }

    @Test func anExpiredTurnIsTakenOver() async throws {
        let second = await mac("B")
        let lease = FetchLease(device: "A", expiresAt: clock.date.addingTimeInterval(-1))
        _ = server.put(SyncRecordName.lease(cursor), payload: try SyncCoding.encode(lease))

        await second.scheduledRefresh()

        #expect(second.fetcher.callCount == 1)
    }

    @Test func theTurnIsHandedBackAfterAFetch() async throws {
        let first = await mac("A")

        await first.scheduledRefresh()

        let lease = try SyncCoding.decode(FetchLease.self, from: try #require(server.payload(SyncRecordName.lease(cursor))))
        #expect(lease.expiresAt <= clock.date)
    }

    @Test func withoutICloudEachMacFetchesForItself() async {
        let second = await mac("B")
        server.isReachable = false

        await second.scheduledRefresh()

        #expect(second.fetcher.callCount == 1)
    }

    @Test func aManualRefreshAlwaysAsksAndShares() async {
        let first = await mac("A")
        let second = await mac("B", report: makeReport(77))

        await first.scheduledRefresh()
        clock.advance(10)
        await second.model.refresh(.cursor, manual: true)
        await first.sync.pull()

        #expect(second.fetcher.callCount == 1)
        #expect(first.cursor.report == makeReport(77))
    }

    @Test func settingsOnlyMacsFetchForThemselves() async {
        let first = await mac("A", mode: .settingsOnly)
        let second = await mac("B", mode: .settingsOnly)
        first.local.values[SimulatedMac.cursorToken] = "a"
        second.local.values[SimulatedMac.cursorToken] = "b"

        await first.scheduledRefresh()
        await second.scheduledRefresh()

        #expect(first.fetcher.callCount == 1)
        #expect(second.fetcher.callCount == 1)
        #expect(server.payload(SyncRecordName.usage(cursor)) == nil)
    }

    // MARK: History

    @Test func aMacThatWasAwayGetsTheHistoryItMissed() async {
        let first = await mac("A")
        let sample = UsageSample(date: clock.date, percent: 12)
        first.history.stored = ["weekly": [sample]]

        await first.scheduledRefresh()
        let second = await mac("B")

        #expect(second.history.stored["weekly"]?.contains(sample) == true)
    }

    // MARK: Settings

    @Test func aSettingChangedOnOneMacReachesTheOther() async {
        let first = await mac("A")
        let second = await mac("B")
        var appearance = MenuBarAppearance.default
        appearance.colored.toggle()

        first.model.setGlobalAppearance(appearance)
        await first.sync.pull()
        await second.sync.pull()

        #expect(second.model.globalAppearance == appearance)
    }

    @Test func anAppliedSettingIsNotSentBack() async {
        let first = await mac("A")
        let second = await mac("B")
        var appearance = MenuBarAppearance.default
        appearance.colored.toggle()
        first.model.setGlobalAppearance(appearance)
        await first.sync.pull()
        let saves = server.saveCount

        await second.sync.pull()
        await second.sync.pull()

        #expect(server.saveCount == saves)
    }

    @Test func joiningTakesWhatICloudAlreadyHolds() async {
        let first = await mac("A", mode: .settingsOnly)
        var appearance = MenuBarAppearance.default
        appearance.colored.toggle()
        first.model.setGlobalAppearance(appearance)
        await first.sync.pull()

        let second = await mac("B", mode: .off)
        await second.sync.setMode(.settingsOnly)

        #expect(second.model.globalAppearance == appearance)
    }

    @Test func offTouchesNothing() async {
        let mac = await mac("A", mode: .off)
        var appearance = MenuBarAppearance.default
        appearance.colored.toggle()

        mac.model.setGlobalAppearance(appearance)
        await mac.scheduledRefresh()

        #expect(server.entries.isEmpty)
        #expect(mac.transport.prepareCount == 0)
        #expect(mac.sync.status == .off)
    }

    // MARK: Session starts

    @Test func onlyOneMacMayStartASession() async {
        let first = await mac("A")
        let second = await mac("B")

        let firstClaimed = await first.sync.claimSessionStart(.anthropic, within: 600)
        let secondClaimed = await second.sync.claimSessionStart(.anthropic, within: 600)
        clock.advance(601)
        let laterClaimed = await second.sync.claimSessionStart(.anthropic, within: 600)

        #expect(firstClaimed)
        #expect(!secondClaimed)
        #expect(laterClaimed)
    }

    // MARK: Availability

    @Test func aBuildWithoutICloudOffersOnlyOff() {
        let sync = SyncCoordinator(
            transport: nil, credentials: nil,
            preferences: MemorySyncPreferencesStore(mode: .everything, deviceID: "A")
        )

        #expect(sync.mode == .off)
        #expect(!sync.isAvailable(.settingsOnly))
        #expect(sync.unavailableReason(.settingsOnly) != nil)
    }

    @Test func signedOutOfICloudSaysSo() async {
        server.account = .noAccount
        let mac = await mac("A")

        #expect(mac.sync.status == .unavailable("Sign in to iCloud in System Settings to sync."))
    }
}

@Suite @MainActor struct SyncSectionTests {
    @Test func theFooterSaysWhatIsSharedAndHowItIsGoing() {
        let off = SyncSection.footer(mode: .off, status: .off, reason: nil)
        let everything = SyncSection.footer(mode: .everything, status: .upToDate(.now), reason: nil)
        let failing = SyncSection.footer(mode: .settingsOnly, status: .failed("Can't reach iCloud right now."), reason: nil)

        #expect(off.hasPrefix("Nothing leaves this Mac."))
        #expect(everything.hasSuffix("Up to date."))
        #expect(failing.contains("Each Mac keeps its own credentials"))
        #expect(failing.hasSuffix("Can't reach iCloud right now."))
    }

    @Test func aBuildThatCannotSyncSaysWhyWhileOff() {
        let footer = SyncSection.footer(mode: .off, status: .off, reason: "Builds made from source don't sync.")

        #expect(footer.hasSuffix("Builds made from source don't sync."))
    }
}

@Suite @MainActor struct SettingsOnlyCatchUpTests {
    @Test func aScheduledRefreshPicksUpAnotherMacsSettings() async {
        let server = InMemorySyncServer()
        let keychain = MemoryCredentialStore()
        let clock = TestClock()
        let first = SimulatedMac("A", server: server, sharedKeychain: keychain, clock: clock, mode: .settingsOnly)
        let second = SimulatedMac("B", server: server, sharedKeychain: keychain, clock: clock, mode: .settingsOnly)
        await first.sync.start()
        await second.sync.start()
        var appearance = MenuBarAppearance.default
        appearance.colored.toggle()

        first.model.setGlobalAppearance(appearance)
        await first.sync.pull()
        await second.scheduledRefresh()

        #expect(second.model.globalAppearance == appearance)
    }
}

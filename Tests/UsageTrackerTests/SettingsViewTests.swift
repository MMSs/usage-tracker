import CoreGraphics
import Testing
@testable import UsageTracker

@Suite @MainActor struct SettingsViewTests {
    @Test func theMenuBarTabIsTitledOptions() {
        #expect(ProviderSettingsTab.menuBar.title == "Options")
    }

    @Test func eachHalfTabHasARefreshSection() {
        #expect(ProviderSettingsTab.subscription.sections == ["Refresh"])
        #expect(ProviderSettingsTab.api.sections == ["Refresh"])
        #expect(ProviderSettingsTab.menuBar.sections == ["Alerts", "Appearance"])
    }

    @Test func requestedProviderPageWhenListed() {
        let request = SettingsRequest(provider: .anthropic)

        #expect(SettingsPage.resolve(request, listed: [.cursor, .anthropic]) == .provider(.anthropic))
    }

    @Test func fallsBackToGeneral() {
        #expect(SettingsPage.resolve(SettingsRequest(provider: .openai), listed: [.cursor]) == .general)
        #expect(SettingsPage.resolve(.general, listed: [.cursor]) == .general)
    }

    @Test func setUpOpensHelpOnTheRequestedProvidersFirstField() {
        let cursor = ProviderRegistry.descriptor(for: .cursor)
        let anthropic = ProviderRegistry.descriptor(for: .anthropic)

        #expect(SettingsHelp.fieldID(for: cursor, helpProvider: .cursor) == "session-token")
        #expect(SettingsHelp.fieldID(for: anthropic, helpProvider: .anthropic) == "session-key")
        #expect(SettingsHelp.fieldID(for: cursor, helpProvider: nil) == nil)
        #expect(SettingsHelp.fieldID(for: anthropic, helpProvider: .cursor) == nil)
    }

    @Test func selectionAppliesRequestsAndDropsHelpWhenLeavingThePage() {
        let selection = SettingsSelection()

        selection.apply(SettingsRequest(provider: .cursor, opensHelp: true), listed: [.cursor])
        #expect(selection.page == .provider(.cursor))
        #expect(selection.helpProvider == .cursor)

        selection.apply(SettingsRequest(provider: .cursor, opensHelp: false), listed: [.cursor])
        #expect(selection.helpProvider == nil)

        selection.apply(SettingsRequest(provider: .openai, opensHelp: true), listed: [.cursor])
        #expect(selection.page == .general)
    }

    private func makeProvider(_ id: Provider, subscription: Bool, api: Bool) -> ProviderViewModel {
        ProviderViewModel(
            descriptor: ProviderRegistry.descriptor(for: id),
            subscriptionFetcher: subscription ? StubReportFetcher(result: .success(makeReport(1))) : nil,
            apiFetcher: api ? StubReportFetcher(result: .success(makeReport(2))) : nil,
            credentialStore: MemoryCredentialStore(), cache: MemoryReportCache()
        )
    }

    @Test func providerTabsFollowTheHalvesTheProviderHas() {
        #expect(ProviderSettingsTab.tabs(for: makeProvider(.cursor, subscription: true, api: false)) == [.subscription, .menuBar])
        #expect(ProviderSettingsTab.tabs(for: makeProvider(.anthropic, subscription: true, api: true)) == [.subscription, .api, .menuBar])
        #expect(ProviderSettingsTab.tabs(for: makeProvider(.anthropic, subscription: false, api: true)) == [.api, .menuBar])
    }

    @Test func aFieldIsOnItsHalfsTab() {
        let cursor = ProviderRegistry.descriptor(for: .cursor)
        let anthropic = ProviderRegistry.descriptor(for: .anthropic)

        #expect(ProviderSettingsTab.holding(fieldID: "session-token", in: cursor) == .subscription)
        #expect(ProviderSettingsTab.holding(fieldID: "session-key", in: anthropic) == .subscription)
        #expect(ProviderSettingsTab.holding(fieldID: "admin-key", in: anthropic) == .api)
        #expect(ProviderSettingsTab.holding(fieldID: "api-budget", in: anthropic) == .api)
        #expect(ProviderSettingsTab.holding(fieldID: "admin-key", in: cursor) == nil)
    }

    @Test func aTabThePageLacksFallsBackToTheFirst() {
        let tabs: [ProviderSettingsTab] = [.subscription, .menuBar]

        #expect(ProviderSettingsTab.resolve(nil, in: tabs) == .subscription)
        #expect(ProviderSettingsTab.resolve(.api, in: tabs) == .subscription)
        #expect(ProviderSettingsTab.resolve(.menuBar, in: tabs) == .menuBar)
    }

    @Test func aHelpRequestSelectsTheTabHoldingTheField() {
        let selection = SettingsSelection()
        selection.selectTab(.menuBar, for: .anthropic)

        selection.apply(SettingsRequest(provider: .anthropic, opensHelp: true), listed: [.anthropic])
        #expect(selection.tabs[.anthropic] == .subscription)

        selection.selectTab(.api, for: .anthropic)
        selection.apply(SettingsRequest(provider: .anthropic, opensHelp: false), listed: [.anthropic])
        #expect(selection.tabs[.anthropic] == .api, "a plain request keeps the tab")

        selection.apply(SettingsRequest(provider: .anthropic, opensHelp: true), listed: [.cursor])
        #expect(selection.tabs[.anthropic] == .api, "an unlisted provider's tab is left alone")
    }

    @Test func pickingATabClosesThatProvidersHelp() {
        let selection = SettingsSelection()
        selection.apply(SettingsRequest(provider: .anthropic, opensHelp: true), listed: [.anthropic])

        selection.selectTab(.subscription, for: .cursor)
        #expect(selection.helpProvider == .anthropic)

        selection.selectTab(.menuBar, for: .anthropic)
        #expect(selection.helpProvider == nil)
        #expect(selection.tabs[.anthropic] == .menuBar)
    }

    private func makeModel(configured: [CredentialKey]) -> AppModel {
        let credentials = MemoryCredentialStore()
        for key in configured {
            credentials.values[key] = "secret"
        }
        let providers = ProviderRegistry.all.map { descriptor in
            ProviderViewModel(
                descriptor: descriptor,
                subscriptionFetcher: StubReportFetcher(result: .success(makeReport(1))),
                apiFetcher: StubReportFetcher(result: .success(makeReport(2))),
                credentialStore: credentials, cache: MemoryReportCache()
            )
        }

        return AppModel(
            providers: providers,
            credentialStore: credentials,
            providerSettingsStore: MemoryProviderSettingsStore(),
            appearanceStore: MemoryMenuBarAppearanceStore(),
            budgetStore: MemoryAPIBudgetStore(),
            loginItem: .stub(),
            sleepObserver: ControllableSleepObserver(),
            networkObserver: ControllableNetworkObserver()
        )
    }

    @Test func generalPreviewShowsEveryEnabledConfiguredProviderLeftToRightAsOnScreen() {
        let model = makeModel(configured: [
            CredentialKey(provider: .openai, fieldID: "admin-key"),
            CredentialKey(provider: .cursor, fieldID: "session-token"),
        ])

        #expect(model.insertedProviders == [.cursor, .openai])
        #expect(GeneralSettingsView.previewProviders(in: model).map(\.id) == [.openai, .cursor], "later items sit further left")

        model.provider(.cursor).isEnabled = false
        #expect(GeneralSettingsView.previewProviders(in: model).map(\.id) == [.openai])

        model.providers.forEach { $0.isEnabled = false }
        #expect(GeneralSettingsView.previewProviders(in: model).isEmpty)
    }

    @Test func generalPreviewIsEmptyWhenNothingIsConfigured() {
        let model = makeModel(configured: [])

        #expect(model.insertedProviders == [.cursor], "the menu bar keeps a set-up item")
        #expect(GeneralSettingsView.previewProviders(in: model).isEmpty)
    }

    @Test func previewItemsScaleDownTogetherOnlyWhenTheyOverflow() {
        let fit = MenuBarPreviewStrip.fit

        #expect(fit([100, 80], 10, 400) == .init(scale: 1, hidden: 0))
        #expect(fit([100, 80], 10, 190) == .init(scale: 1, hidden: 0))
        #expect(fit([90, 90], 20, 160) == .init(scale: 0.8, hidden: 0))
        #expect(fit([], 10, 100) == .init(scale: 1, hidden: 0))
    }

    @Test func rowsThatFitAboveTheMinimumScaleHideNothingDespiteRounding() {
        // 71.5 + 12 + 101 + 12 + 103.5 = 300; times 254.5 / 300 it comes to 254.50000000000003.
        #expect(MenuBarPreviewStrip.fit(widths: [71.5, 101, 103.5], spacing: 12, available: 254.5).hidden == 0)

        // Half-point widths, as rendered items have, from a fixed generator so every run is the same.
        var seed: UInt64 = 42
        func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(1 << 53)
        }
        func halfPoints(_ value: Double) -> CGFloat {
            CGFloat((value * 2).rounded() / 2)
        }

        var spurious: [[CGFloat]] = []
        for _ in 0 ..< 1_000 {
            let widths = (0 ..< 3).map { _ in halfPoints(40 + next() * 160) }
            let natural = MenuBarPreviewStrip.naturalWidth(widths, spacing: 12)
            // Between the minimum scale and full size, so the row always fits shrunk.
            let available = halfPoints(Double(natural) * (0.72 + next() * 0.27))
            if MenuBarPreviewStrip.fit(widths: widths, spacing: 12, available: available).hidden != 0 {
                spurious.append(widths + [available])
            }
        }

        #expect(spurious.isEmpty, "\(spurious.count) rows: \(spurious.prefix(3))")
    }

    @Test func previewItemsBelowTheMinimumScaleDropFromTheLeft() {
        let fit = MenuBarPreviewStrip.fit

        // 100 + 10 + 100 + 10 + 100 = 320; at 0.7 that is 224, too wide for 200.
        #expect(fit([100, 100, 100], 10, 200) == .init(scale: 0.7, hidden: 1))
        // At 0.7 the last item alone is 140; nothing fits in 100.
        #expect(fit([100, 200], 10, 100) == .init(scale: 0.7, hidden: 2))
    }

    @Test func helpOnAnAPIOnlyProviderSelectsTheAPITab() {
        let anthropic = ProviderRegistry.descriptor(for: .anthropic)
        let apiOnly = ProviderDescriptor(
            id: .anthropic,
            displayName: "Anthropic",
            capabilities: ProviderCapabilities(
                hasSubscription: false, hasAPISpend: true, hasCycle: false, hasDailyChart: true, canStartSession: false
            ),
            fields: anthropic.apiFields,
            services: anthropic.services,
            shortWindowID: nil,
            longWindowID: "weekly",
            meterNames: MeterNames(short: "Session", long: "Weekly")
        )

        #expect(SettingsHelp.tab(for: apiOnly, helpProvider: .anthropic) == .api)
        #expect(SettingsHelp.tab(for: anthropic, helpProvider: .anthropic) == .subscription)
        #expect(SettingsHelp.tab(for: apiOnly, helpProvider: .cursor) == nil)
    }
}

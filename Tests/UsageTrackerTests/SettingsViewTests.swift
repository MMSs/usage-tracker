import Testing
@testable import UsageTracker

@Suite @MainActor struct SettingsViewTests {
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

    @Test func generalPreviewShowsEveryEnabledConfiguredProviderInMenuBarOrder() {
        let model = makeModel(configured: [
            CredentialKey(provider: .openai, fieldID: "admin-key"),
            CredentialKey(provider: .cursor, fieldID: "session-token"),
        ])

        #expect(GeneralSettingsView.previewProviders(in: model).map(\.id) == [.cursor, .openai])

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
        #expect(MenuBarPreviewStrip.scale(widths: [100, 80], spacing: 10, available: 400) == 1)
        #expect(MenuBarPreviewStrip.scale(widths: [100, 80], spacing: 10, available: 190) == 1)
        #expect(MenuBarPreviewStrip.scale(widths: [190, 190], spacing: 20, available: 200) == 0.5)
        #expect(MenuBarPreviewStrip.scale(widths: [], spacing: 10, available: 100) == 1)
    }
}

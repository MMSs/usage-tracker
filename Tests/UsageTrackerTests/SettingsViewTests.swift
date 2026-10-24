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

    @Test func generalPreviewSkipsDisabledProviders() {
        let credentials = MemoryCredentialStore()
        credentials.values[CredentialKey(provider: .cursor, fieldID: "session-token")] = "secret"
        let providers = ProviderRegistry.all.map { descriptor in
            ProviderViewModel(
                descriptor: descriptor,
                subscriptionFetcher: StubReportFetcher(result: .success(makeReport(1))),
                apiFetcher: nil,
                credentialStore: credentials, cache: MemoryReportCache()
            )
        }

        #expect(GeneralSettingsView.previewProvider(from: providers)?.id == .cursor)

        providers[0].isEnabled = false
        #expect(GeneralSettingsView.previewProvider(from: providers)?.id == .anthropic)

        providers.forEach { $0.isEnabled = false }
        #expect(GeneralSettingsView.previewProvider(from: providers) == nil)
    }
}

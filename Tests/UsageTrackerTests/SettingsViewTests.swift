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
}

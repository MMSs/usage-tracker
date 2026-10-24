import Testing
@testable import UsageTracker

@Suite @MainActor struct SettingsViewTests {
    @Test func focusIsTheExpandedProviderWhenListed() {
        #expect(SettingsView.focusedProvider(expanded: .anthropic, listed: [.cursor, .anthropic]) == .anthropic)
    }

    @Test func focusFallsBackToTheFirstListedProvider() {
        #expect(SettingsView.focusedProvider(expanded: .openai, listed: [.cursor]) == .cursor)
        #expect(SettingsView.focusedProvider(expanded: .openai, listed: []) == nil)
    }

    @Test func setUpOpensHelpOnTheFocusedProvidersFirstField() {
        let cursor = ProviderRegistry.descriptor(for: .cursor)
        let anthropic = ProviderRegistry.descriptor(for: .anthropic)

        #expect(SettingsView.helpFieldID(for: cursor, focused: .cursor, openHelp: true) == "session-token")
        #expect(SettingsView.helpFieldID(for: anthropic, focused: .anthropic, openHelp: true) == "session-key")
        #expect(SettingsView.helpFieldID(for: cursor, focused: .cursor, openHelp: false) == nil)
        #expect(SettingsView.helpFieldID(for: anthropic, focused: .cursor, openHelp: true) == nil)
    }
}

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
}

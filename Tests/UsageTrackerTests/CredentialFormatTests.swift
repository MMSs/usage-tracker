import Testing
@testable import UsageTracker

struct CredentialFormatTests {
    @Test func formatProblemNamesTheMissingTokens() {
        let message = "Paste the whole auth.json file. It needs tokens.access_token and tokens.refresh_token."

        #expect(CredentialFormat.codexAuthJSON.problem(with: "not json") == message)
        #expect(CredentialFormat.codexAuthJSON.problem(with: #"{"tokens":{"access_token":"fake-access"}}"#) == message)
        #expect(CredentialFormat.codexAuthJSON.problem(
            with: #"{"tokens":{"access_token":"fake-access","refresh_token":"fake-refresh"}}"#
        ) == nil)
    }

    @Test func plainFormatAcceptsAnything() {
        #expect(CredentialFormat.plain.problem(with: "anything at all") == nil)
    }

    @Test func openAIAuthFieldUsesTheCodexFormat() throws {
        let field = try #require(ProviderRegistry.descriptor(for: .openai).fields.first { $0.id == "auth-json" })

        #expect(field.format == .codexAuthJSON)
    }
}

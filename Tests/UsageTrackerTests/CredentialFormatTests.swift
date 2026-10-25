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

    @Test func codexAuthIsMaskedByItsRefreshToken() throws {
        let json = #"{"auth_mode":"chatgpt","tokens":{"access_token":"eyJhbGciOi.fake","refresh_token":"rt_fakeRefresh9876"}}"#
        let mask = try #require(CredentialFormat.codexAuthJSON.mask(of: json))

        #expect(mask.prefix == "rt_fak")
        #expect(mask.suffix == "9876")
    }

    @Test func unreadableCodexAuthShowsOnlyEllipses() {
        #expect(CredentialFormat.codexAuthJSON.mask(of: #"{"tokens":null}"#) == .hidden)
        #expect(CredentialFormat.codexAuthJSON.mask(of: "") == nil)
    }

    @Test func plainFormatMasksTheWholeValue() {
        #expect(CredentialFormat.plain.mask(of: "abcdefghijklmnop") == CredentialMask(value: "abcdefghijklmnop"))
    }

    @Test func openAIAuthFieldUsesTheCodexFormat() throws {
        let field = try #require(ProviderRegistry.descriptor(for: .openai).fields.first { $0.id == "auth-json" })

        #expect(field.format == .codexAuthJSON)
    }
}

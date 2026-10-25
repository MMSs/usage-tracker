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

    @Test func codexAuthIsShownAsJSONWithEverySecretMasked() throws {
        let json = #"""
        {"OPENAI_API_KEY":null,"auth_mode":"chatgpt","last_refresh":"2026-10-25T09:00:00.000Z",
         "tokens":{"access_token":"eyJhbGciOiJSUzI1NiJ9.payload.sigAAAA","account_id":"acct-fake-123456",
                   "id_token":"eyJhbGciOiJSUzI1NiJ9.idpayload.sigBBBB","refresh_token":"rt_Kp2Lq3Mr4Ns5Ot6"},
         "future_field":"secret-looking-value"}
        """#
        let document = try #require(CredentialFormat.codexAuthJSON.mask(of: json)?.document)

        #expect(document == """
        {
          "auth_mode" : "chatgpt",
          "future_field" : "secret………alue",
          "last_refresh" : "2026-10-25T09:00:00.000Z",
          "OPENAI_API_KEY" : null,
          "tokens" : {
            "access_token" : "eyJhbG………AAAA",
            "account_id" : "acct-f………3456",
            "id_token" : "eyJhbG………BBBB",
            "refresh_token" : "rt_Kp2L………5Ot6"
          }
        }
        """)
    }

    @Test func unreadableCodexAuthShowsOnlyEllipses() {
        #expect(CredentialFormat.codexAuthJSON.mask(of: #"{"tokens":null}"#) == .hidden)
        #expect(CredentialFormat.codexAuthJSON.mask(of: "") == nil)
    }

    @Test func plainFormatMasksTheWholeValue() {
        #expect(CredentialFormat.plain.mask(of: "abcdefghijklmnop") == CredentialMask(value: "abcdefghijklmnop"))
        #expect(CredentialFormat.plain.mask(of: "abcdefghijklmnop")?.document == nil)
    }

    @Test func openAIAuthFieldUsesTheCodexFormat() throws {
        let field = try #require(ProviderRegistry.descriptor(for: .openai).fields.first { $0.id == "auth-json" })

        #expect(field.format == .codexAuthJSON)
    }
}

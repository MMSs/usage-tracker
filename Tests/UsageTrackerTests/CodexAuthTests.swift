import Foundation
import Testing
@testable import UsageTracker

struct CodexAuthTests {
    private static func base64URL(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static let bundle = """
    {"auth_mode":"chatgpt","OPENAI_API_KEY":null,"future_field":{"a":1},
     "last_refresh":"2026-01-01T00:00:00.000Z",
     "tokens":{"access_token":"fake-access","refresh_token":"fake-refresh","id_token":"fake-id","account_id":"acct-file"}}
    """

    private static func object(_ json: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    @Test func parsesTokensAndAccountID() throws {
        let auth = try CodexAuth(json: Self.bundle)

        #expect(auth.accessToken == "fake-access")
        #expect(auth.refreshToken == "fake-refresh")
        #expect(auth.accountID == "acct-file")
    }

    @Test func accountIDFallsBackToTheJWTClaim() throws {
        let payload = Self.base64URL(#"{"https://api.openai.com/auth":{"chatgpt_account_id":"acct-jwt"}}"#)
        let json = #"{"tokens":{"access_token":"header.\#(payload).sig","refresh_token":"fake-refresh"}}"#

        #expect(try CodexAuth(json: json).accountID == "acct-jwt")
    }

    @Test func missingRefreshTokenIsRejected() {
        #expect(throws: FetchError.unauthorized) {
            try CodexAuth(json: #"{"tokens":{"access_token":"fake-access","refresh_token":"  "}}"#)
        }
    }

    @Test func apiKeyOnlyFileIsRejected() {
        #expect(throws: FetchError.unauthorized) {
            try CodexAuth(json: #"{"OPENAI_API_KEY":"sk-fake","tokens":null}"#)
        }
    }

    @Test func renewalKeepsUnknownFields() throws {
        let grant = CodexTokenGrant(idToken: "new-id", accessToken: "new-access", refreshToken: "new-refresh")
        let renewed = try CodexAuth.renewedJSON(Self.bundle, grant: grant, at: Date(timeIntervalSince1970: 0))
        let root = try Self.object(renewed)
        let tokens = try #require(root["tokens"] as? [String: Any])

        #expect(root["auth_mode"] as? String == "chatgpt")
        #expect(root["OPENAI_API_KEY"] is NSNull)
        #expect(root["future_field"] != nil)
        #expect(tokens["account_id"] as? String == "acct-file")
        #expect(tokens["access_token"] as? String == "new-access")
        #expect(tokens["refresh_token"] as? String == "new-refresh")
        #expect(tokens["id_token"] as? String == "new-id")
    }

    @Test func renewalKeepsValuesTheGrantOmits() throws {
        let grant = CodexTokenGrant(idToken: nil, accessToken: "new-access", refreshToken: nil)
        let renewed = try CodexAuth.renewedJSON(Self.bundle, grant: grant, at: Date(timeIntervalSince1970: 0))
        let tokens = try #require(try Self.object(renewed)["tokens"] as? [String: Any])

        #expect(tokens["access_token"] as? String == "new-access")
        #expect(tokens["refresh_token"] as? String == "fake-refresh")
        #expect(tokens["id_token"] as? String == "fake-id")
    }

    @Test func renewalStampsLastRefresh() throws {
        let grant = CodexTokenGrant(idToken: nil, accessToken: "new-access", refreshToken: nil)
        let renewed = try CodexAuth.renewedJSON(Self.bundle, grant: grant, at: Date(timeIntervalSince1970: 1_000_000_000.5))

        #expect(try Self.object(renewed)["last_refresh"] as? String == "2001-09-09T01:46:40.500Z")
    }
}

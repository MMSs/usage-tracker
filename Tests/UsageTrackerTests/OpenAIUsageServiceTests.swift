import Foundation
import Testing
@testable import UsageTracker

@MainActor
struct OpenAIUsageServiceTests {
    private func fixture(_ name: String) throws -> String {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))

        return try String(contentsOf: url, encoding: .utf8)
    }

    private func auth(accountID: String?) throws -> CodexAuth {
        let account = accountID.map { #","account_id":"\#($0)""# } ?? ""

        return try CodexAuth(json: #"{"tokens":{"access_token":"test-access","refresh_token":"test-refresh"\#(account)}}"#)
    }

    @Test
    func usageRequestCarriesTheRecipe() async throws {
        let client = try RecordingHTTPClient(response: .ok(json: fixture("openai-wham-usage")))

        let response = try await OpenAIUsageService(client: client).fetchUsage(auth: try auth(accountID: "acct-1"))

        let request = try #require(client.lastRequest)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        #expect(request.url?.absoluteString == "https://chatgpt.com/backend-api/wham/usage")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-access")
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "acct-1")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "UsageTracker/\(version) (https://github.com/MMSs/usage-tracker)")
        #expect(response.planType == "plus")
    }

    @Test(arguments: [
        #"{"rate_limit":{"primary_window":{"used_percent":3,"limit_window_seconds":18000,"reset_at":"soon"}}}"#,
        #"{"rate_limit":{"secondary_window":{"used_percent":3,"limit_window_seconds":604800,"reset_at":"soon"}}}"#,
    ])
    func anUnreadableSessionResetIsADecodingError(json: String) async throws {
        let service = OpenAIUsageService(client: RecordingHTTPClient(response: .ok(json: json)))

        await #expect(throws: FetchError.decoding) {
            try await service.fetchUsage(auth: try auth(accountID: "acct-1"))
        }
    }

    @Test
    func missingAccountIDOmitsTheHeader() async throws {
        let client = try RecordingHTTPClient(response: .ok(json: fixture("openai-wham-usage")))

        _ = try await OpenAIUsageService(client: client).fetchUsage(auth: try auth(accountID: nil))

        let request = try #require(client.lastRequest)
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == nil)
    }

    @Test
    func unauthorizedUsageIsAnExpiredAccessToken() async {
        let service = OpenAIUsageService(client: RecordingHTTPClient(response: .status(401)))

        await #expect(throws: OpenAIUsageError.accessTokenExpired) {
            try await service.fetchUsage(auth: try auth(accountID: "acct-1"))
        }
    }

    @Test
    func jsonForbiddenIsUnauthorizedNotExpired() async {
        let client = RecordingHTTPClient(response: .status(403, headers: ["Content-Type": "application/json"]))
        let service = OpenAIUsageService(client: client)

        await #expect(throws: FetchError.unauthorized) {
            try await service.fetchUsage(auth: try auth(accountID: "acct-1"))
        }
    }

    @Test
    func htmlChallengeIsChallenge() async {
        let client = RecordingHTTPClient(response: .status(403, headers: ["Content-Type": "text/html"]))
        let service = OpenAIUsageService(client: client)

        await #expect(throws: FetchError.challenge) {
            try await service.fetchUsage(auth: try auth(accountID: "acct-1"))
        }
    }

    // MARK: Starting a session

    /// The recipe's body, with the test model.
    private static let codexBody = """
        {"model":"test-model","stream":true,"store":false,"parallel_tool_calls":false,
         "reasoning":{"effort":"low"},
         "input":[{"type":"message","role":"user","content":[{"type":"input_text","text":"ping"}]}]}
        """

    private static func object(_ data: Data?) throws -> NSDictionary {
        let data = try #require(data)

        return try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    @Test
    func startingASessionSendsTheCodexRequest() async throws {
        let client = RecordingHTTPClient(response: .ok(json: "event: response.completed\ndata: {}\n\n"))

        try await OpenAIUsageService(client: client).startSession(auth: try auth(accountID: "acct-1"), model: "test-model")

        let request = try #require(client.lastRequest)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        #expect(request.url?.absoluteString == "https://chatgpt.com/backend-api/codex/responses")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-access")
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "acct-1")
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "UsageTracker/\(version) (https://github.com/MMSs/usage-tracker)")
        #expect(request.value(forHTTPHeaderField: "originator") == nil)

        let body = try Self.object(request.httpBody)
        #expect(body == (try Self.object(Data(Self.codexBody.utf8))))
        #expect(body["instructions"] == nil)
        // NSNumber equality would also take 1 and 0 for the flags.
        let text = try #require(request.httpBody.map { String(decoding: $0, as: UTF8.self) })
        #expect(text.contains(#""stream":true"#))
        #expect(text.contains(#""store":false"#))
        #expect(text.contains(#""parallel_tool_calls":false"#))
    }

    @Test
    func aStartWithoutAnAccountIDOmitsTheHeader() async throws {
        let client = RecordingHTTPClient(response: .ok(json: ""))

        try await OpenAIUsageService(client: client).startSession(auth: try auth(accountID: nil), model: "test-model")

        let request = try #require(client.lastRequest)
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == nil)
    }

    @Test
    func aRefusedStartIsItsStatus() async {
        let client = RecordingHTTPClient(response: .status(400, headers: ["Content-Type": "application/json"]))
        let service = OpenAIUsageService(client: client)

        await #expect(throws: FetchError.httpStatus(400)) {
            try await service.startSession(auth: try auth(accountID: "acct-1"), model: "test-model")
        }
    }

    @Test
    func anUnauthorizedStartIsAnExpiredAccessToken() async {
        let service = OpenAIUsageService(client: RecordingHTTPClient(response: .status(401)))

        await #expect(throws: OpenAIUsageError.accessTokenExpired) {
            try await service.startSession(auth: try auth(accountID: "acct-1"), model: "test-model")
        }
    }
}

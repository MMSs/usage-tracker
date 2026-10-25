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
}

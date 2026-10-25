import Foundation
import Testing
@testable import UsageTracker

@MainActor
struct OpenAITokenServiceTests {
    private func fixture(_ name: String) throws -> String {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))

        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test
    func refreshPostsTheCodexBody() async throws {
        let client = try RecordingHTTPClient(response: .ok(json: fixture("openai-token-refresh")))

        let grant = try await OpenAITokenService(client: client).renew(refreshToken: "test-refresh")

        let request = try #require(client.lastRequest)
        #expect(request.url?.absoluteString == "https://auth.openai.com/oauth/token")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(request.httpBody)
        let sent = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(sent == [
            "client_id": "app_EMoamEEZ73f0CkXaXp7hrann",
            "grant_type": "refresh_token",
            "refresh_token": "test-refresh",
        ])
        #expect(grant.accessToken == "new-access")
        #expect(grant.refreshToken == "new-refresh")
    }

    @Test(arguments: [400, 401])
    func rejectedRefreshIsUnauthorized(status: Int) async {
        let service = OpenAITokenService(client: RecordingHTTPClient(response: .status(status)))

        await #expect(throws: FetchError.unauthorized) {
            try await service.renew(refreshToken: "test-refresh")
        }
    }

    @Test
    func serverErrorDuringRefreshIsNotExpiry() async {
        let service = OpenAITokenService(client: RecordingHTTPClient(response: .status(503)))

        await #expect(throws: FetchError.httpStatus(503)) {
            try await service.renew(refreshToken: "test-refresh")
        }
    }

    @Test
    func grantWithoutAccessTokenIsDecodingError() async {
        let client = RecordingHTTPClient(response: .ok(json: #"{"refresh_token":"new-refresh"}"#))
        let service = OpenAITokenService(client: client)

        await #expect(throws: FetchError.decoding) {
            try await service.renew(refreshToken: "test-refresh")
        }
    }
}

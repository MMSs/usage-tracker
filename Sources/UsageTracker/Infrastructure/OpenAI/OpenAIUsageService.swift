import Foundation

/// wham/usage answered 401: the access token expired, which renewing it fixes.
/// A JSON 403 stays `FetchError.unauthorized`; a new token cannot fix it.
enum OpenAIUsageError: Error, Equatable {
    case accessTokenExpired
}

@MainActor
protocol OpenAIUsageFetching {
    /// Throws `OpenAIUsageError.accessTokenExpired` on 401.
    func fetchUsage(auth: CodexAuth) async throws -> OpenAIUsageResponse
}

@MainActor
final class OpenAIUsageService: OpenAIUsageFetching {
    private static let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    private let client: HTTPClient

    init(client: HTTPClient = URLSessionHTTPClient()) {
        self.client = client
    }

    func fetchUsage(auth: CodexAuth) async throws -> OpenAIUsageResponse {
        let data = try await HTTPResponseHandler.data(
            for: request(auth: auth),
            client: client,
            overrides: [401: OpenAIUsageError.accessTokenExpired]
        )

        return try HTTPResponseHandler.decode(OpenAIUsageResponse.self, from: data)
    }

    private func request(auth: CodexAuth) -> URLRequest {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        if let accountID = auth.accountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(RequestSupport.userAgent, forHTTPHeaderField: "User-Agent")

        return request
    }
}

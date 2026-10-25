import Foundation

@MainActor
protocol OpenAIUsageFetching {
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
        let data = try await HTTPResponseHandler.data(for: request(auth: auth), client: client)

        return try HTTPResponseHandler.decode(OpenAIUsageResponse.self, from: data)
    }

    private func request(auth: CodexAuth) -> URLRequest {
        var request = URLRequest(url: Self.endpoint)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        request.httpMethod = "GET"
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        if let accountID = auth.accountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("UsageTracker/\(version) (https://github.com/MMSs/usage-tracker)", forHTTPHeaderField: "User-Agent")

        return request
    }
}

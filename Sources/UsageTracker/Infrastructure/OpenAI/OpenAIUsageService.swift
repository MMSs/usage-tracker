import Foundation

/// The ChatGPT backend answered 401: the access token expired, which renewing it fixes.
/// A JSON 403 stays `FetchError.unauthorized`; a new token cannot fix it.
enum OpenAIUsageError: Error, Equatable {
    case accessTokenExpired
}

@MainActor
protocol OpenAIUsageFetching {
    /// Throws `OpenAIUsageError.accessTokenExpired` on 401.
    func fetchUsage(auth: CodexAuth) async throws -> OpenAIUsageResponse
    /// Opens the 5-hour session with one Codex request. Throws
    /// `OpenAIUsageError.accessTokenExpired` on 401.
    func startSession(auth: CodexAuth, model: String) async throws
}

@MainActor
final class OpenAIUsageService: OpenAIUsageFetching {
    private static let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private static let responsesEndpoint = URL(string: "https://chatgpt.com/backend-api/codex/responses")!

    private let client: HTTPClient

    init(client: HTTPClient = URLSessionHTTPClient()) {
        self.client = client
    }

    func fetchUsage(auth: CodexAuth) async throws -> OpenAIUsageResponse {
        let data = try await send(request(url: Self.endpoint, auth: auth))

        let usage = try HTTPResponseHandler.decode(OpenAIUsageResponse.self, from: data)

        // An unreadable reset would read as a closed session, which auto-start acts on.
        if usage.primary?.hasUnreadableReset == true || usage.secondary?.hasUnreadableReset == true {
            Log.http.error("usage response has an unreadable reset time")
            throw FetchError.decoding
        }

        return usage
    }

    func startSession(auth: CodexAuth, model: String) async throws {
        var request = request(url: Self.responsesEndpoint, auth: auth, accept: "text/event-stream")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.responsesBody(model: model)

        // The reply is a stream of events ending in response.completed;
        // reading it to the end is all a session start needs.
        _ = try await send(request)
    }

    /// The backend takes only a streamed, unstored response, and rejects
    /// `instructions` and an output cap.
    private static func responsesBody(model: String) throws -> Data {
        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "store": false,
            "parallel_tool_calls": false,
            "reasoning": ["effort": "low"],
            "input": [[
                "type": "message",
                "role": "user",
                "content": [["type": "input_text", "text": "ping"]],
            ]],
        ]

        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    private func send(_ request: URLRequest) async throws -> Data {
        try await HTTPResponseHandler.data(
            for: request,
            client: client,
            overrides: [401: OpenAIUsageError.accessTokenExpired]
        )
    }

    private func request(url: URL, auth: CodexAuth, accept: String = "application/json") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        if let accountID = auth.accountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(RequestSupport.userAgent, forHTTPHeaderField: "User-Agent")

        return request
    }
}

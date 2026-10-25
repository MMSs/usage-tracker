import Foundation

@MainActor
protocol OpenAITokenRenewing {
    /// Spends `refreshToken`, which is single-use. Throws
    /// `FetchError.unauthorized` when it is rejected and
    /// `FetchError.decoding` when the grant carries no access token.
    func renew(refreshToken: String) async throws -> CodexTokenGrant
}

@MainActor
final class OpenAITokenService: OpenAITokenRenewing {
    private static let endpoint = URL(string: "https://auth.openai.com/oauth/token")!
    /// The public client id of the Codex CLI, whose login this app borrows.
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    private let client: HTTPClient

    init(client: HTTPClient = URLSessionHTTPClient()) {
        self.client = client
    }

    func renew(refreshToken: String) async throws -> CodexTokenGrant {
        let data: Data
        do {
            data = try await HTTPResponseHandler.data(for: request(refreshToken: refreshToken), client: client)
        } catch FetchError.httpStatus(400) {
            // A refresh token that is expired, reused or revoked answers 400.
            throw FetchError.unauthorized
        }

        let grant = try HTTPResponseHandler.decode(CodexTokenGrant.self, from: data)

        // The old access token is no use; a grant without a new one is a shape change.
        guard grant.accessToken != nil else {
            Log.http.error("token response carries no access token")
            throw FetchError.decoding
        }

        return grant
    }

    private func request(refreshToken: String) throws -> URLRequest {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(RequestSupport.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": Self.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])

        return request
    }
}

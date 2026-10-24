import Foundation

@MainActor
protocol AnthropicUsageFetching {
    func fetchSubscription(sessionKey: String) async throws -> AnthropicSubscriptionSnapshot
}

final class AnthropicUsageService: AnthropicUsageFetching {
    private static let baseURL = "https://claude.ai/api"
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    private struct Organization {
        let uuid: String
        let planName: String?
    }

    private let client: HTTPClient
    private var organization: Organization?
    /// The session key `organization` was resolved with; another key is
    /// another account.
    private var organizationSessionKey: String?

    init(client: HTTPClient = URLSessionHTTPClient()) {
        self.client = client
    }

    func fetchSubscription(sessionKey: String) async throws -> AnthropicSubscriptionSnapshot {
        var organization = try await resolveOrganization(sessionKey: sessionKey)
        let usage: AnthropicUsageResponse

        do {
            usage = try await fetchUsage(organization: organization, sessionKey: sessionKey)
        } catch let error as FetchError where Self.isStaleOrganization(error) {
            // The cached organization may be gone; resolve it once more.
            self.organization = nil
            organization = try await resolveOrganization(sessionKey: sessionKey)
            usage = try await fetchUsage(organization: organization, sessionKey: sessionKey)
        }

        // Accounts without extra usage answer these with 403 or 404; that is not an error.
        let spendLimit = try await fetchOptional(
            AnthropicOverageSpendLimit.self,
            path: "organizations/\(organization.uuid)/overage_spend_limit",
            sessionKey: sessionKey
        )
        let creditGrant = try await fetchOptional(
            AnthropicOverageCreditGrant.self,
            path: "organizations/\(organization.uuid)/overage_credit_grant",
            sessionKey: sessionKey
        )

        return AnthropicSubscriptionSnapshot(
            usage: usage,
            planName: organization.planName,
            spendLimit: spendLimit,
            creditGrant: creditGrant
        )
    }

    private static func isStaleOrganization(_ error: FetchError) -> Bool {
        switch error {
        case .unauthorized, .httpStatus(404), .decoding:
            true
        default:
            false
        }
    }

    private func resolveOrganization(sessionKey: String) async throws -> Organization {
        if organizationSessionKey != sessionKey {
            organization = nil
        }

        if let organization {
            return organization
        }

        let data = try await send(request(path: "organizations", sessionKey: sessionKey))
        let response = try HTTPResponseHandler.decode(AnthropicOrganizationsResponse.self, from: data)

        // A session with no organization has nothing to report.
        guard let chosen = response.primary else {
            throw FetchError.decoding
        }

        let resolved = Organization(
            uuid: chosen.uuid,
            planName: AnthropicPlanName.from(rateLimitTier: chosen.rateLimitTier, capabilities: chosen.capabilities)
        )
        organization = resolved
        organizationSessionKey = sessionKey

        return resolved
    }

    private func fetchUsage(organization: Organization, sessionKey: String) async throws -> AnthropicUsageResponse {
        let data = try await send(request(path: "organizations/\(organization.uuid)/usage", sessionKey: sessionKey))

        // The default decoder would silently drop every resets_at.
        let usage: AnthropicUsageResponse
        do {
            usage = try AnthropicUsageResponse.decoder().decode(AnthropicUsageResponse.self, from: data)
        } catch {
            throw FetchError.decoding
        }

        // A response with neither window is a shape change, not an idle account.
        guard usage.fiveHour != nil || usage.sevenDay != nil else {
            throw FetchError.decoding
        }

        return usage
    }

    /// Nil on any failure except cancellation.
    private func fetchOptional<T: Decodable>(_ type: T.Type, path: String, sessionKey: String) async throws -> T? {
        do {
            let data = try await send(request(path: path, sessionKey: sessionKey))

            return try HTTPResponseHandler.decode(type, from: data)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }

    private func request(path: String, sessionKey: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "\(Self.baseURL)/\(path)")!)
        request.httpMethod = "GET"
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        try await HTTPResponseHandler.data(for: request, client: client)
    }
}

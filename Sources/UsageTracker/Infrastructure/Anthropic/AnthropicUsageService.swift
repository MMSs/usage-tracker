import Foundation
import os

@MainActor
protocol AnthropicUsageFetching {
    /// What the last listing found for `sessionKey`; empty when it was not the last one listed.
    func organizations(sessionKey: String) -> [AnthropicOrganizationsResponse.Organization]
    /// `organizationID` is the user's choice. A lone organization is used
    /// whatever it is; with several, one of them must be chosen, or this
    /// throws `FetchError.needsOrganizationChoice` without fetching usage.
    func fetchSubscription(sessionKey: String, organizationID: String?) async throws -> AnthropicSubscriptionSnapshot
}

final class AnthropicUsageService: AnthropicUsageFetching {
    private static let baseURL = "https://claude.ai/api"
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    private struct Organization {
        let uuid: String
        let planName: String?
    }

    private let client: HTTPClient
    private var listedOrganizations: [AnthropicOrganizationsResponse.Organization] = []
    /// The session key `listedOrganizations` belongs to; another key is
    /// another account.
    private var listedSessionKey: String?
    /// False when the listing may be out of date, so the next fetch lists again.
    private var listingIsCurrent = false

    init(client: HTTPClient = URLSessionHTTPClient()) {
        self.client = client
    }

    func organizations(sessionKey: String) -> [AnthropicOrganizationsResponse.Organization] {
        listedSessionKey == sessionKey ? listedOrganizations : []
    }

    func fetchSubscription(
        sessionKey: String,
        organizationID: String? = nil
    ) async throws -> AnthropicSubscriptionSnapshot {
        var organization = try await resolveOrganization(sessionKey: sessionKey, organizationID: organizationID)
        let usage: AnthropicUsageResponse

        do {
            usage = try await fetchUsage(organization: organization, sessionKey: sessionKey)
        } catch let error as FetchError where Self.isStaleOrganization(error) {
            // The listed organization may be gone; list them once more.
            listingIsCurrent = false
            organization = try await resolveOrganization(sessionKey: sessionKey, organizationID: organizationID)
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

    /// Lists the organizations once per session key, then takes the chosen
    /// one, or the only one.
    private func resolveOrganization(sessionKey: String, organizationID: String?) async throws -> Organization {
        if listedSessionKey != sessionKey || !listingIsCurrent {
            let data = try await send(request(path: "organizations", sessionKey: sessionKey))
            let response = try HTTPResponseHandler.decode(AnthropicOrganizationsResponse.self, from: data)
            listedOrganizations = response.organizations
            listedSessionKey = sessionKey
            listingIsCurrent = true
        }

        // A session with no organization has nothing to report.
        guard !listedOrganizations.isEmpty else {
            listingIsCurrent = false
            Log.http.error("organizations response lists no usable organization")
            throw FetchError.decoding
        }

        let chosen = listedOrganizations.first { $0.uuid == organizationID }
            ?? (listedOrganizations.count == 1 ? listedOrganizations[0] : nil)

        guard let chosen else {
            // Listed again next time, so a manual refresh sees a membership change.
            listingIsCurrent = false
            let count = listedOrganizations.count
            Log.http.info("\(count, privacy: .public) organizations and none chosen; waiting for a choice")
            throw FetchError.needsOrganizationChoice
        }

        return Organization(
            uuid: chosen.uuid,
            planName: AnthropicPlanName.from(rateLimitTier: chosen.rateLimitTier, capabilities: chosen.capabilities)
        )
    }

    private func fetchUsage(organization: Organization, sessionKey: String) async throws -> AnthropicUsageResponse {
        let data = try await send(request(path: "organizations/\(organization.uuid)/usage", sessionKey: sessionKey))

        // The default decoder would silently drop every resets_at.
        let usage: AnthropicUsageResponse
        do {
            usage = try AnthropicUsageResponse.decoder().decode(AnthropicUsageResponse.self, from: data)
        } catch {
            HTTPResponseHandler.logDecodingFailure(error, decoding: AnthropicUsageResponse.self)
            throw FetchError.decoding
        }

        // A response with neither window is a shape change, not an idle account.
        guard usage.fiveHour != nil || usage.sevenDay != nil else {
            Log.http.error("usage response has neither the 5-hour nor the weekly window")
            throw FetchError.decoding
        }

        // An unreadable reset would read as a closed session, which auto-start acts on.
        if usage.fiveHour?.hasUnreadableReset == true || usage.sevenDay?.hasUnreadableReset == true {
            Log.http.error("usage response has an unreadable reset time")
            throw FetchError.decoding
        }

        return usage
    }

    /// Nil on any failure except cancellation.
    private func fetchOptional<T: Decodable>(_ type: T.Type, path: String, sessionKey: String) async throws -> T? {
        do {
            let data = try await send(request(path: path, sessionKey: sessionKey))

            return try HTTPResponseHandler.decode(type, from: data, optional: true)
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

import Foundation

@MainActor
protocol UsageFetching {
    func fetchUsage(token: String) async throws -> CursorUsageResponse
}

@MainActor
protocol DailySpendFetching {
    func fetchDailySpend(token: String, periodStart: Date, periodEnd: Date) async throws -> DailySpendResponse
    /// When the user joined the team; nothing earlier can have data.
    func membershipStart(token: String) async throws -> Date?
}

final class CursorUsageService: UsageFetching, DailySpendFetching {
    private static let endpoint = URL(string: "https://cursor.com/api/usage-summary")!

    private let client: HTTPClient

    init(client: HTTPClient = URLSessionHTTPClient()) {
        self.client = client
    }

    private var identity: Identity?

    func fetchUsage(token: String) async throws -> CursorUsageResponse {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.setValue(
            "WorkosCursorSessionToken=\(token)",
            forHTTPHeaderField: "Cookie"
        )

        let data = try await send(request)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(CursorUsageResponse.self, from: data)
        } catch {
            throw FetchError.decoding
        }
    }

    func membershipStart(token: String) async throws -> Date? {
        try await resolveIdentity(token: token).membershipStart
    }

    func fetchDailySpend(token: String, periodStart: Date, periodEnd: Date) async throws -> DailySpendResponse {
        let calendar = Calendar.current
        let startMs = CursorDayConversion.apiMilliseconds(forLocalDay: periodStart, calendar: calendar)
        let endMs = CursorDayConversion.apiMilliseconds(forLocalDay: periodEnd, calendar: calendar) - 1

        do {
            return try await requestDailySpend(token: token, startMs: startMs, endMs: endMs)
        } catch FetchError.httpStatus, FetchError.decoding {
            // Cached identifiers may be stale; resolve them once more.
            identity = nil
            return try await requestDailySpend(token: token, startMs: startMs, endMs: endMs)
        }
    }

    private func requestDailySpend(token: String, startMs: Int64, endMs: Int64) async throws -> DailySpendResponse {
        let ids = try await resolveIdentity(token: token)
        var body: [String: Any] = [
            "periodStartMs": startMs,
            "periodEndMs": endMs,
            "groupBy": 1,
            "spendType": 2,
        ]
        // Personal accounts have no team; the endpoint scopes to the caller.
        if let team = ids.team {
            body["teamId"] = team.teamId
            body["userId"] = team.userId
        }
        let data = try await send(post("get-daily-spend-by-category", token: token, body: body))

        return try decode(DailySpendResponse.self, from: data)
    }

    private func resolveIdentity(token: String) async throws -> Identity {
        if let identity {
            return identity
        }

        let organizations = try decode(
            OrganizationsResponse.self,
            from: try await send(post("get-user-organizations", token: token, body: [:]))
        )

        guard let firstTeam = organizations.organizations?.first?.teams?.first else {
            let personal = Identity(team: nil, membershipStart: nil)
            identity = personal

            return personal
        }

        let teamId = firstTeam.teamId

        let team = try decode(
            TeamResponse.self,
            from: try await send(post("team", token: token, body: ["teamId": teamId]))
        )
        let resolved = Identity(
            team: .init(teamId: teamId, userId: team.userId),
            membershipStart: firstTeam.teamOrganizationMembershipCreatedAtMs
                .flatMap(Double.init)
                .map { Date(timeIntervalSince1970: $0 / 1000) }
        )
        identity = resolved

        return resolved
    }

    private func post(_ path: String, token: String, body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://cursor.com/api/dashboard/\(path)")!)
        request.httpMethod = "POST"
        request.setValue("WorkosCursorSessionToken=\(token)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.setValue("https://cursor.com/dashboard", forHTTPHeaderField: "Referer")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return request
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw FetchError.decoding
        }
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await client.data(for: request)
        } catch {
            throw FetchError.transport
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FetchError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            switch httpResponse.statusCode {
            case 401:
                throw FetchError.unauthorized
            case 403:
                // An HTML 403 is a bot-protection challenge, not an expired session.
                let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
                if contentType.hasPrefix("text/html") {
                    throw FetchError.challenge
                }
                throw FetchError.unauthorized
            default:
                break
            }

            throw FetchError.httpStatus(httpResponse.statusCode)
        }

        return data
    }
}

private struct OrganizationsResponse: Decodable {
    struct Organization: Decodable {
        struct Team: Decodable {
            let teamId: Int
            let teamOrganizationMembershipCreatedAtMs: String?
        }

        let teams: [Team]?
    }

    let organizations: [Organization]?
}

private struct TeamResponse: Decodable {
    let userId: Int
}

private struct Identity {
    struct Team {
        let teamId: Int
        let userId: Int
    }

    /// Nil for personal accounts, which belong to no team.
    let team: Team?
    let membershipStart: Date?
}

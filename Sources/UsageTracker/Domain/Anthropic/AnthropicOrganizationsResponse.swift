import Foundation

/// The accounts a claude.ai session belongs to. Unknown keys are ignored.
struct AnthropicOrganizationsResponse: Equatable, Sendable {
    struct Organization: Equatable, Sendable {
        let uuid: String
        var name: String? = nil
        var rateLimitTier: String? = nil
        var capabilities: [String]? = nil
    }

    let organizations: [Organization]
}

extension AnthropicOrganizationsResponse.Organization: Decodable {
    private enum CodingKeys: String, CodingKey {
        case uuid, name, capabilities
        case rateLimitTier = "rate_limit_tier"
    }
}

extension AnthropicOrganizationsResponse: Decodable {
    private enum CodingKeys: String, CodingKey {
        case organizations
    }

    /// The endpoint returns a bare array; an `{ "organizations": [...] }`
    /// envelope is accepted too.
    init(from decoder: Decoder) throws {
        if let array = try? decoder.singleValueContainer().decode([Organization].self) {
            organizations = array
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            organizations = try container.decode([Organization].self, forKey: .organizations)
        }
    }
}

enum AnthropicPlanName {
    // Order matters: "max_20x" and "max_5x" are checked before "pro".
    private static let plans: [(marker: String, name: String)] = [
        ("max_20x", "Max 20x"),
        ("max_5x", "Max 5x"),
        ("pro", "Pro"),
        ("team", "Team"),
        ("enterprise", "Enterprise"),
    ]

    /// The rate-limit tier names the plan most reliably; capabilities are
    /// the fallback when the tier is missing or unrecognised.
    static func from(rateLimitTier: String?, capabilities: [String]?) -> String? {
        let sources = [rateLimitTier ?? ""] + (capabilities ?? [])
        for source in sources {
            let lowered = source.lowercased()
            if let plan = plans.first(where: { lowered.contains($0.marker) }) {
                return plan.name
            }
        }

        return nil
    }
}

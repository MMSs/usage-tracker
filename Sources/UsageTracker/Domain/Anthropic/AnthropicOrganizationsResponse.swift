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
    private struct Plan {
        let name: String
        /// Matched as a case-insensitive substring of the rate-limit tier.
        let tierMarker: String?
        /// Matched against whole capability tokens, so "project" is never "pro".
        let capabilityMatches: @Sendable (String) -> Bool
    }

    // Highest plan first; the first plan any source matches wins. A bare
    // `claude_max` capability cannot tell 5x from 20x, so it is just "Max".
    private static let plans: [Plan] = [
        Plan(name: "Max 20x", tierMarker: "max_20x") { $0.contains("max_20x") },
        Plan(name: "Max 5x", tierMarker: "max_5x") { $0.contains("max_5x") },
        Plan(name: "Max", tierMarker: nil) { $0 == "claude_max" },
        Plan(name: "Enterprise", tierMarker: "enterprise") { $0 == "claude_enterprise" },
        Plan(name: "Team", tierMarker: "team") { $0 == "claude_team" },
        Plan(name: "Pro", tierMarker: "pro") { $0 == "claude_pro" },
    ]

    /// The rate-limit tier and the capabilities both name the plan; the
    /// highest plan either one matches wins, whatever the order.
    static func from(rateLimitTier: String?, capabilities: [String]?) -> String? {
        let tier = (rateLimitTier ?? "").lowercased()
        let tokens = (capabilities ?? []).map { $0.lowercased() }

        return plans.first { plan in
            if let marker = plan.tierMarker, tier.contains(marker) {
                return true
            }

            return tokens.contains(where: plan.capabilityMatches)
        }?.name
    }
}

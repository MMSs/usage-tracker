import Foundation

/// The accounts a claude.ai session belongs to. Unknown keys are ignored.
struct AnthropicOrganizationsResponse: Equatable, Sendable {
    struct Organization: Equatable, Sendable {
        let uuid: String
        var name: String? = nil
        var rateLimitTier: String? = nil
        var capabilities: [String]? = nil
        /// The plan as claude.ai names it, when it sends one.
        var planDisplayName: String? = nil
        var planDisplayLabel: String? = nil
    }

    let organizations: [Organization]
}

extension AnthropicOrganizationsResponse.Organization: Decodable {
    private enum CodingKeys: String, CodingKey {
        case uuid, name, capabilities
        case rateLimitTier = "rate_limit_tier"
        case planDisplayName = "plan_display_name"
        case planDisplayLabel = "plan_display_label"
    }
}

extension AnthropicOrganizationsResponse.Organization {
    /// Tells same-named organizations apart: "API" for one without chat
    /// (a Console organization), else its plan when the tier names one.
    var detail: String? {
        if let capabilities, !capabilities.contains("chat") {
            return "API"
        }

        return planName
    }

    /// The server's own plan name when it sends one, so a renamed or new
    /// plan shows without an app update; otherwise the tier's plan.
    var planName: String? {
        let sent = [planDisplayName, planDisplayLabel]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        return sent ?? AnthropicPlanName.from(rateLimitTier: rateLimitTier, capabilities: capabilities)
    }
}

extension AnthropicOrganizationsResponse: Decodable {
    private enum CodingKeys: String, CodingKey {
        case organizations
    }

    /// An element that fails to decode is skipped instead of failing the list.
    private struct LossyOrganization: Decodable {
        let organization: Organization?

        init(from decoder: Decoder) throws {
            organization = try? Organization(from: decoder)
        }
    }

    /// The endpoint returns a bare array; an `{ "organizations": [...] }`
    /// envelope is accepted too.
    init(from decoder: Decoder) throws {
        let elements: [LossyOrganization]
        if let array = try? decoder.singleValueContainer().decode([LossyOrganization].self) {
            elements = array
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            elements = try container.decode([LossyOrganization].self, forKey: .organizations)
        }
        organizations = elements.compactMap(\.organization)
    }
}

enum AnthropicPlanName {
    private struct Plan {
        let name: String
        /// Any one matched as a case-insensitive substring of the rate-limit tier.
        let tierMarkers: [String]
        /// Matched against whole capability tokens, so "project" is never "pro".
        let capabilityMatches: @Sendable (String) -> Bool
    }

    // Highest plan first; the first plan any source matches wins, so the
    // bare "max" marker only sees tiers Ultra has already passed over.
    // Max 20x became Ultra and Max 5x became Max when the plans were renamed.
    private static let plans: [Plan] = [
        Plan(name: "Ultra", tierMarkers: ["ultra", "max_20x"]) { $0 == "claude_ultra" || $0.contains("max_20x") },
        Plan(name: "Max", tierMarkers: ["max"]) { $0 == "claude_max" || $0.contains("max_5x") },
        Plan(name: "Enterprise", tierMarkers: ["enterprise"]) { $0 == "claude_enterprise" },
        Plan(name: "Team", tierMarkers: ["team"]) { $0 == "claude_team" },
        Plan(name: "Pro", tierMarkers: ["pro"]) { $0 == "claude_pro" },
        Plan(name: "Free", tierMarkers: ["free"]) { $0 == "claude_free" },
    ]

    /// The rate-limit tier and the capabilities both name the plan; the
    /// highest plan either one matches wins, whatever the order.
    static func from(rateLimitTier: String?, capabilities: [String]?) -> String? {
        let tier = (rateLimitTier ?? "").lowercased()
        let tokens = (capabilities ?? []).map { $0.lowercased() }

        return plans.first { plan in
            if plan.tierMarkers.contains(where: { tier.contains($0) }) {
                return true
            }

            return tokens.contains(where: plan.capabilityMatches)
        }?.name
    }
}

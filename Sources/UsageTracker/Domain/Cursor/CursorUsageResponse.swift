import Foundation

struct CursorUsageResponse: Decodable, Equatable {
    struct IndividualUsage: Decodable, Equatable {
        struct Overall: Decodable, Equatable {
            let used: Int
            let limit: Int?
            /// Share of included usage consumed; personal plans report it
            /// in place of a dollar limit.
            var percentUsed: Decimal? = nil
            var percentSplit: PercentSplit? = nil
        }

        let overall: Overall
    }

    let billingCycleStart: Date
    let billingCycleEnd: Date
    let individualUsage: IndividualUsage
    let isUnlimited: Bool
    /// The plan's key, such as `free` or `pro_plus`; absent on old responses.
    var membershipType: String? = nil
}

// Cursor's JSON omits zero-valued fields. Team plans report `overall`;
// personal plans report `plan`, where a zero limit means no dollar budget.
extension CursorUsageResponse.IndividualUsage {
    private enum CodingKeys: String, CodingKey {
        case overall, plan
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let key: CodingKeys = container.contains(.overall) ? .overall : .plan
        overall = try container.decode(Overall.self, forKey: key)
    }
}

extension CursorUsageResponse.IndividualUsage.Overall {
    private enum CodingKeys: String, CodingKey {
        case used, limit
        case percentUsed = "totalPercentUsed"
        case autoPercentUsed, apiPercentUsed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        used = try container.decodeIfPresent(Int.self, forKey: .used) ?? 0
        limit = try container.decodeIfPresent(Int.self, forKey: .limit).flatMap { $0 > 0 ? $0 : nil }
        percentUsed = try container.decodeIfPresent(Decimal.self, forKey: .percentUsed)
        percentSplit = percentUsed == nil ? nil : PercentSplit(
            auto: try container.decodeIfPresent(Decimal.self, forKey: .autoPercentUsed) ?? 0,
            api: try container.decodeIfPresent(Decimal.self, forKey: .apiPercentUsed) ?? 0
        )
    }
}

/// Personal plans meter Auto (and Composer) separately from named API
/// models; each is a percentage of its own included allowance.
struct PercentSplit: Equatable {
    let auto: Decimal
    let api: Decimal
}

enum CursorPlanName {
    /// Cursor's plans by their membership keys; Hobby is what the free
    /// plan is called on the pricing page.
    private static let known: [String: String] = [
        "free": "Hobby",
        "hobby": "Hobby",
        "free_trial": "Pro Trial",
        "pro": "Pro",
        "pro_plus": "Pro+",
        "ultra": "Ultra",
        "team": "Teams",
        "teams": "Teams",
        "business": "Business",
        "enterprise": "Enterprise",
    ]

    /// A key the table does not know still reads as a name ("pro_max"
    /// becomes "Pro max"), so a new plan shows without an app update.
    static func from(membershipType: String?) -> String? {
        guard let key = membershipType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !key.isEmpty else {
            return nil
        }

        if let name = known[key] {
            return name
        }

        let words = key.replacingOccurrences(of: "_", with: " ")

        return words.prefix(1).uppercased() + words.dropFirst()
    }
}

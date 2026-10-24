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

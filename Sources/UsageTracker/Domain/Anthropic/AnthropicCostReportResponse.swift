import Foundation

/// One page of the Admin API cost report. Unknown keys are ignored.
struct AnthropicCostReportResponse: Decodable, Equatable, Sendable {
    struct Bucket: Decodable, Equatable, Sendable {
        let startingAt: Date
        let endingAt: Date
        /// Empty when the bucket has no `results`, or a null one.
        let results: [Result]

        private enum CodingKeys: String, CodingKey {
            case startingAt = "starting_at"
            case endingAt = "ending_at"
            case results
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            startingAt = try container.decode(Date.self, forKey: .startingAt)
            endingAt = try container.decode(Date.self, forKey: .endingAt)
            results = try container.decodeIfPresent([Result].self, forKey: .results) ?? []
        }
    }

    struct Result: Decodable, Equatable, Sendable {
        let currency: String?
        /// A decimal string in cents; nil when the amount is null or absent.
        let amount: String?

        private enum CodingKeys: String, CodingKey {
            case currency, amount
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            currency = try container.decodeIfPresent(String.self, forKey: .currency)

            // Documented as a string; a JSON number is read as its decimal
            // text so no precision is lost. Any other type still throws, so
            // a cost is never silently dropped.
            if try !container.contains(.amount) || container.decodeNil(forKey: .amount) {
                amount = nil
            } else if let text = try? container.decode(String.self, forKey: .amount) {
                amount = text
            } else {
                amount = "\(try container.decode(Decimal.self, forKey: .amount))"
            }
        }
    }

    let data: [Bucket]
    let hasMore: Bool
    let nextPage: String?

    private enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}

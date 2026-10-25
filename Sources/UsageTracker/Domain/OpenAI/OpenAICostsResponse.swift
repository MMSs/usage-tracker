import Foundation

/// One page of the Admin API costs report. Unknown keys are ignored.
struct OpenAICostsResponse: Decodable, Equatable, Sendable {
    struct Bucket: Decodable, Equatable, Sendable {
        let startTime: Date
        /// Empty when the bucket has no `results`, or a null one.
        let results: [Result]

        private enum CodingKeys: String, CodingKey {
            case startTime = "start_time"
            case results
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            startTime = Date(timeIntervalSince1970: try container.decode(TimeInterval.self, forKey: .startTime))
            results = try container.decodeIfPresent([Result].self, forKey: .results) ?? []
        }
    }

    struct Result: Decodable, Equatable, Sendable {
        /// Dollars; nil when the amount is absent, null or not a decimal number.
        let amount: Decimal?
        let currency: String?

        private enum CodingKeys: String, CodingKey {
            case amount, currency
        }

        private enum AmountKeys: String, CodingKey {
            case value, currency
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard let nested = try? container.nestedContainer(keyedBy: AmountKeys.self, forKey: .amount) else {
                amount = nil
                currency = nil

                return
            }

            currency = try? nested.decodeIfPresent(String.self, forKey: .currency)

            // Decimal's own Decodable reads the number token without a Double round trip.
            if let number = try? nested.decode(Decimal.self, forKey: .value) {
                amount = number
            } else if let text = try? nested.decode(String.self, forKey: .value) {
                amount = RequestSupport.decimal(fromNumericString: text)
            } else {
                amount = nil
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

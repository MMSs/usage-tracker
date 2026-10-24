import Foundation

/// One page of the Admin API cost report. Unknown keys are ignored.
struct AnthropicCostReportResponse: Decodable, Equatable, Sendable {
    struct Bucket: Decodable, Equatable, Sendable {
        let startingAt: Date
        let endingAt: Date
        let results: [Result]

        private enum CodingKeys: String, CodingKey {
            case startingAt = "starting_at"
            case endingAt = "ending_at"
            case results
        }
    }

    struct Result: Decodable, Equatable, Sendable {
        let currency: String?
        /// A decimal string in cents.
        let amount: String
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

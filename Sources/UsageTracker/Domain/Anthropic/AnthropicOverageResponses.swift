import Foundation

/// The monthly overage ("extra usage") spend limit and what has been used.
struct AnthropicOverageSpendLimit: Equatable, Sendable {
    let isEnabled: Bool
    let usedCredits: Double
    let monthlyCreditLimit: Double
    let currency: String?
}

extension AnthropicOverageSpendLimit: Decodable {
    private enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case usedCredits = "used_credits"
        case monthlyCreditLimit = "monthly_credit_limit"
        case currency
    }

    // An unset limit or untouched usage may arrive as null; both read as zero.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        usedCredits = container.decodeLossyNumber(forKey: .usedCredits) ?? 0
        monthlyCreditLimit = container.decodeLossyNumber(forKey: .monthlyCreditLimit) ?? 0
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
    }
}

/// Prepaid overage credits granted to the account.
struct AnthropicOverageCreditGrant: Equatable, Sendable {
    let remainingBalance: Double
    let totalGranted: Double?
    let currency: String?
}

extension AnthropicOverageCreditGrant: Decodable {
    private enum CodingKeys: String, CodingKey {
        case remainingBalance = "remaining_balance"
        case totalGranted = "total_granted"
        case currency
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let balance = container.decodeLossyNumber(forKey: .remainingBalance) else {
            throw DecodingError.keyNotFound(CodingKeys.remainingBalance, .init(
                codingPath: decoder.codingPath,
                debugDescription: "remaining_balance is missing or not numeric"
            ))
        }
        remainingBalance = balance
        totalGranted = container.decodeLossyNumber(forKey: .totalGranted)
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
    }
}

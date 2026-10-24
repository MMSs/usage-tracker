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

/// Prepaid overage credits granted to the account. The live response carries
/// more (`available`, `eligible`, `needs_payment_setup`, `feature`,
/// `expires_at`); only what the report needs is read, and every field is
/// lossy so a null or reshaped one never fails the decode.
struct AnthropicOverageCreditGrant: Equatable, Sendable {
    let granted: Bool?
    /// Minor units of `currency` (cents for USD).
    let amountMinorUnits: Double?
    let currency: String?

    /// The granted amount in major units, or nil when no credit is granted.
    /// Always cents-to-dollars: the only currency seen is USD, and a
    /// different `currency` is not converted.
    var grantedAmount: Double? {
        guard granted == true, let amountMinorUnits else {
            return nil
        }

        return amountMinorUnits / 100
    }
}

extension AnthropicOverageCreditGrant: Decodable {
    private enum CodingKeys: String, CodingKey {
        case granted
        case amountMinorUnits = "amount_minor_units"
        case currency
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        granted = (try? container.decodeIfPresent(Bool.self, forKey: .granted)) ?? nil
        amountMinorUnits = container.decodeLossyNumber(forKey: .amountMinorUnits)
        currency = (try? container.decodeIfPresent(String.self, forKey: .currency)) ?? nil
    }
}

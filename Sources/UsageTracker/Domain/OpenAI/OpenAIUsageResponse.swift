import Foundation

/// ChatGPT's private `wham/usage` response, as Codex reads it. Decoding is
/// deliberately tolerant: numbers arrive as numbers or strings, and a
/// malformed window, entry or `credits` is dropped rather than failing the
/// report. Identity fields (`user_id`, `account_id`, `email`) are not decoded.
struct OpenAIUsageResponse: Equatable, Sendable {
    struct Window: Equatable, Sendable {
        let usedPercent: Double?
        let windowSeconds: Int?
        let resetAt: Date?
    }

    struct AdditionalLimit: Equatable, Sendable {
        let name: String
        let primary: Window?
        let secondary: Window?
    }

    struct Credits: Equatable, Sendable {
        let hasCredits: Bool
        let unlimited: Bool
        let balance: Decimal?
    }

    let planType: String?
    let primary: Window?
    let secondary: Window?
    let additional: [AdditionalLimit]
    let credits: Credits?
}

/// The two windows of a `rate_limit` object.
private struct OpenAIRateLimit: Decodable {
    let primary: OpenAIUsageResponse.Window?
    let secondary: OpenAIUsageResponse.Window?

    private enum CodingKeys: String, CodingKey {
        case primary = "primary_window"
        case secondary = "secondary_window"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        primary = (try? container.decodeIfPresent(OpenAIUsageResponse.Window.self, forKey: .primary)) ?? nil
        secondary = (try? container.decodeIfPresent(OpenAIUsageResponse.Window.self, forKey: .secondary)) ?? nil
    }
}

extension OpenAIUsageResponse.Window: Decodable {
    private enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowSeconds = "limit_window_seconds"
        case resetAt = "reset_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = container.decodeLossyNumber(forKey: .usedPercent)
        windowSeconds = container.decodeLossyNumber(forKey: .windowSeconds).flatMap { Int(exactly: $0.rounded()) }
        resetAt = container.decodeLossyNumber(forKey: .resetAt).map { Date(timeIntervalSince1970: $0) }
    }
}

extension OpenAIUsageResponse.AdditionalLimit: Decodable {
    private enum CodingKeys: String, CodingKey {
        case name = "limit_name"
        case rateLimit = "rate_limit"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        let rateLimit = (try? container.decodeIfPresent(OpenAIRateLimit.self, forKey: .rateLimit)) ?? nil
        primary = rateLimit?.primary
        secondary = rateLimit?.secondary
    }
}

extension OpenAIUsageResponse.Credits: Decodable {
    private enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited
        case balance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasCredits = (try? container.decodeIfPresent(Bool.self, forKey: .hasCredits)) ?? false
        unlimited = (try? container.decodeIfPresent(Bool.self, forKey: .unlimited)) ?? false

        // The balance is a decimal string ("12.50"); a JSON number is accepted too.
        if let text = try? container.decodeIfPresent(String.self, forKey: .balance) {
            balance = Decimal(string: text.trimmingCharacters(in: .whitespaces), locale: Locale(identifier: "en_US_POSIX"))
        } else {
            balance = (try? container.decodeIfPresent(Decimal.self, forKey: .balance)) ?? nil
        }
    }
}

extension OpenAIUsageResponse: Decodable {
    private enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case additional = "additional_rate_limits"
        case credits
    }

    /// Wraps an `additional_rate_limits[]` element so one malformed entry
    /// becomes nil instead of failing the array.
    private struct LossyLimit: Decodable {
        let limit: AdditionalLimit?

        init(from decoder: Decoder) {
            limit = try? AdditionalLimit(from: decoder)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        planType = (try? container.decodeIfPresent(String.self, forKey: .planType)) ?? nil
        let rateLimit = (try? container.decodeIfPresent(OpenAIRateLimit.self, forKey: .rateLimit)) ?? nil
        primary = rateLimit?.primary
        secondary = rateLimit?.secondary
        let lossyLimits = (try? container.decodeIfPresent([LossyLimit].self, forKey: .additional)) ?? nil
        additional = (lossyLimits ?? []).compactMap(\.limit)
        credits = (try? container.decodeIfPresent(Credits.self, forKey: .credits)) ?? nil
    }
}

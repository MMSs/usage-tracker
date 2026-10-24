import Foundation

/// claude.ai's private usage response. Windows and limits are all optional
/// and decoding is deliberately tolerant: percentages arrive as numbers or
/// strings, and unknown or malformed pieces are dropped rather than failing
/// the whole report.
struct AnthropicUsageResponse: Equatable, Sendable {
    struct UsageWindow: Equatable, Sendable {
        let utilization: Double?
        let resetsAt: Date?
    }

    struct ScopedLimit: Equatable, Sendable {
        let kind: String
        let percent: Double?
        let resetsAt: Date?
        let modelID: String?
        let modelDisplayName: String?
    }

    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let limits: [ScopedLimit]
    /// Older per-model weekly windows (`seven_day_opus`), keyed by suffix.
    let legacyModelWindows: [String: UsageWindow]
}

extension AnthropicUsageResponse {
    /// Decodes the response's ISO 8601 dates, which carry microseconds and a
    /// `+00:00` offset (or milliseconds and `Z`, or no fraction at all).
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = parseDate(text) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unrecognised ISO 8601 date"
                ))
            }

            return date
        }

        return decoder
    }

    // `ISO8601DateFormatter` accepts any number of fractional digits when
    // `.withFractionalSeconds` is set, but rejects strings without a fraction
    // under that option, so the two shapes need separate formatters.
    private static func parseDate(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) {
            return date
        }

        return ISO8601DateFormatter().date(from: text)
    }
}

extension AnthropicUsageResponse.UsageWindow: Decodable {
    private enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        utilization = container.decodeLossyNumber(forKey: .utilization)
        // A bad date costs the countdown, not the whole window.
        resetsAt = (try? container.decodeIfPresent(Date.self, forKey: .resetsAt)) ?? nil
    }
}

extension AnthropicUsageResponse.ScopedLimit: Decodable {
    private enum CodingKeys: String, CodingKey {
        case kind, percent, scope
        case resetsAt = "resets_at"
    }

    private struct Scope: Decodable {
        struct Model: Decodable {
            let id: String?
            let displayName: String?

            private enum CodingKeys: String, CodingKey {
                case id
                case displayName = "display_name"
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? nil
                displayName = (try? container.decodeIfPresent(String.self, forKey: .displayName)) ?? nil
            }
        }

        let model: Model?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        percent = container.decodeLossyNumber(forKey: .percent)
        resetsAt = (try? container.decodeIfPresent(Date.self, forKey: .resetsAt)) ?? nil
        let model = (try? container.decodeIfPresent(Scope.self, forKey: .scope))??.model
        modelID = model?.id
        modelDisplayName = model?.displayName
    }
}

extension AnthropicUsageResponse: Decodable {
    private enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case limits
    }

    private struct DynamicKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            return nil
        }
    }

    /// Wraps a `limits[]` element so one malformed entry becomes nil instead
    /// of failing the array.
    private struct LossyLimit: Decodable {
        let limit: ScopedLimit?

        init(from decoder: Decoder) {
            limit = try? ScopedLimit(from: decoder)
        }
    }

    private static let legacyPrefix = "seven_day_"

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour = (try? container.decodeIfPresent(UsageWindow.self, forKey: .fiveHour)) ?? nil
        sevenDay = (try? container.decodeIfPresent(UsageWindow.self, forKey: .sevenDay)) ?? nil
        let lossyLimits = (try? container.decodeIfPresent([LossyLimit].self, forKey: .limits)) ?? nil
        limits = (lossyLimits ?? []).compactMap(\.limit)

        // `seven_day` itself lacks the trailing underscore, so it never
        // counts as a legacy key. Null and non-object values are skipped.
        let dynamic = try decoder.container(keyedBy: DynamicKey.self)
        var legacy: [String: UsageWindow] = [:]
        for key in dynamic.allKeys where key.stringValue.hasPrefix(Self.legacyPrefix) {
            let suffix = String(key.stringValue.dropFirst(Self.legacyPrefix.count))
            guard !suffix.isEmpty, let window = try? dynamic.decode(UsageWindow.self, forKey: key) else { continue }
            legacy[suffix] = window
        }
        legacyModelWindows = legacy
    }
}

import Foundation

/// A number that APIs send as a JSON number or as a numeric string. Null,
/// non-numeric strings and any other type decode as nil instead of throwing.
struct LossyNumber: Decodable, Equatable, Sendable {
    let value: Double?

    init(value: Double?) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number
        } else if let text = try? container.decode(String.self) {
            value = Double(text.trimmingCharacters(in: .whitespaces))
        } else {
            value = nil
        }
    }
}

extension KeyedDecodingContainer {
    /// The number under `key`, or nil when it is absent, null or not numeric.
    func decodeLossyNumber(forKey key: Key) -> Double? {
        (try? decodeIfPresent(LossyNumber.self, forKey: key))?.value
    }
}

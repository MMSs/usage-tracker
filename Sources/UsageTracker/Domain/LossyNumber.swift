import Foundation

/// A number that APIs send as a JSON number or as a numeric string. Null,
/// non-numeric strings, non-finite values and any other type decode as nil
/// instead of throwing.
struct LossyNumber: Decodable, Equatable, Sendable {
    let value: Double?

    init(value: Double?) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let number: Double?
        if let decoded = try? container.decode(Double.self) {
            number = decoded
        } else if let text = try? container.decode(String.self) {
            // Double("nan") and Double("inf") parse; neither is a usable amount.
            number = Double(text.trimmingCharacters(in: .whitespaces))
        } else {
            number = nil
        }
        value = number.flatMap { $0.isFinite ? $0 : nil }
    }
}

extension KeyedDecodingContainer {
    /// The number under `key`, or nil when it is absent, null or not numeric.
    func decodeLossyNumber(forKey key: Key) -> Double? {
        (try? decodeIfPresent(LossyNumber.self, forKey: key))?.value
    }
}

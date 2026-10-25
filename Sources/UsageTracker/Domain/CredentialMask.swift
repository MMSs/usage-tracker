import Foundation

/// The visible ends of a stored credential, enough to tell which one is in
/// use without exposing it, or for a structured credential a copy of it with
/// every secret reduced to its ends. Only these are kept in memory.
struct CredentialMask: Equatable, Sendable {
    static let ellipsis = "…"

    /// A stored value whose fragments are not worth showing: ellipses only.
    static let hidden = CredentialMask(prefix: "", suffix: "")

    let prefix: String
    let suffix: String
    /// The masked text to show whole instead of the fragments, e.g. a
    /// pretty-printed JSON file whose secrets are masked in place.
    let document: String?

    private init(prefix: String, suffix: String) {
        self.prefix = prefix
        self.suffix = suffix
        document = nil
    }

    /// `document` must already be masked; it is shown as given.
    init(document: String) {
        prefix = ""
        suffix = ""
        self.document = document
    }

    /// Nil for an empty value. A value that opens with a kind prefix such as
    /// `sk-ant-sid01-`, `sk-admin-` or `user_` shows that prefix whole, then 4
    /// characters of the random part and its last 4, so keys of different kinds
    /// from one vendor tell apart. Otherwise long values show 6 and 4
    /// characters, values under 12 show 2 and 2, values under 6 show ellipses
    /// only. Whitespace is skipped so a value pasted with line breaks still
    /// yields one line.
    init?(value: String) {
        let characters = value.filter { !$0.isWhitespace }
        guard !characters.isEmpty else { return nil }

        document = nil

        if let kind = characters.prefixMatch(of: Self.kindPrefix) {
            let random = characters[kind.range.upperBound...]
            if random.count >= Self.shortestRandomPart {
                prefix = String(kind.output) + String(random.prefix(4))
                suffix = String(random.suffix(4))
                return
            }
        }

        switch characters.count {
        case 12...:
            prefix = String(characters.prefix(6))
            suffix = String(characters.suffix(4))
        case 6...:
            prefix = String(characters.prefix(2))
            suffix = String(characters.suffix(2))
        default:
            prefix = ""
            suffix = ""
        }
    }

    /// Lowercase words, each optionally ending in a version number, joined and
    /// ended by `-` or `_`: `sk-ant-admin01-`, `rt_`. A random segment rarely
    /// fits, since it mixes case or puts digits mid-word.
    private static var kindPrefix: Regex<Substring> { /[a-z]{2,8}(?:[-_][a-z]{2,10}[0-9]{0,2})*[-_]/ }

    /// Below this the random part would show most of itself, so the plain
    /// rule applies.
    private static let shortestRandomPart = 8

    /// The fragments joined by `ellipsisCount` ellipses, at least one.
    func text(ellipsisCount: Int) -> String {
        prefix + String(repeating: Self.ellipsis, count: max(1, ellipsisCount)) + suffix
    }

    /// How many ellipses fill `availableWidth`, at least one.
    static func ellipsisCount(availableWidth: CGFloat, ellipsisWidth: CGFloat) -> Int {
        guard ellipsisWidth > 0, availableWidth > 0 else { return 1 }
        return max(1, Int((availableWidth / ellipsisWidth).rounded(.down)))
    }
}

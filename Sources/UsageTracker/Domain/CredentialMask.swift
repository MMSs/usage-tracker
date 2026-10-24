import Foundation

/// The visible ends of a stored credential, enough to tell which one is in
/// use without exposing it. Only these fragments are kept in memory.
struct CredentialMask: Equatable, Sendable {
    static let ellipsis = "…"

    let prefix: String
    let suffix: String

    /// Nil for an empty value. Long values show 6 and 4 characters, values
    /// under 12 show 2 and 2, values under 6 show ellipses only. Whitespace
    /// is skipped so a pasted JSON file still yields one line of fragments.
    init?(value: String) {
        let characters = value.filter { !$0.isWhitespace }
        guard !characters.isEmpty else { return nil }

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

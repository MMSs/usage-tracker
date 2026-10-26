import Foundation

/// A pull request title in the conventional-commit shape the release flow
/// relies on: `type(scope)!: description`.
public struct ConventionalTitle: Equatable, Sendable {
    /// The commit types a title may start with.
    public static let allowedTypes = ["feat", "fix", "perf", "docs", "ci", "chore", "refactor", "test", "build"]

    public let type: String
    public let scope: String?
    public let isBreaking: Bool
    public let description: String

    /// Parses `title`, or returns nil when it does not match
    /// `^(feat|fix|…)(\([a-z0-9-]+\))?(!)?: .+$`. The description is kept
    /// verbatim; nothing in it is interpreted.
    public init?(_ title: String) {
        let pattern = "^(\(Self.allowedTypes.joined(separator: "|")))(?:\\(([a-z0-9-]+)\\))?(!)?: (.+)$"
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
            match.range == NSRange(title.startIndex..., in: title)
        else { return nil }

        func group(_ index: Int) -> String? {
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: title) else { return nil }
            return String(title[swiftRange])
        }
        guard let type = group(1), let description = group(4) else { return nil }
        self.type = type
        scope = group(2)
        isBreaking = group(3) != nil
        self.description = description
    }
}

import Foundation

/// One commit read from `git log --format='%s%x1f%b%x1e'`.
public struct ReleaseCommit: Equatable, Sendable {
    public let subject: String
    public let body: String

    public init(subject: String, body: String) {
        self.subject = subject
        self.body = body
    }

    /// Splits `text` into records at U+001E and fields at U+001F, trimming
    /// whitespace. Empty records (such as after the last separator) are dropped.
    public static func parseLog(_ text: String) -> [ReleaseCommit] {
        text.split(separator: "\u{1E}", omittingEmptySubsequences: true).compactMap { record in
            let fields = record.split(separator: "\u{1F}", maxSplits: 1, omittingEmptySubsequences: false)
            let subject = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !subject.isEmpty else { return nil }
            let body = fields.count > 1 ? fields[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            return ReleaseCommit(subject: subject, body: body)
        }
    }
}

/// One line of the release notes.
public struct ReleaseEntry: Equatable, Sendable {
    public let scope: String?
    public let text: String
    public let pullRequest: Int?
    public let bullets: [String]

    public init(scope: String?, text: String, pullRequest: Int?, bullets: [String]) {
        self.scope = scope
        self.text = text
        self.pullRequest = pullRequest
        self.bullets = bullets
    }
}

/// The version to release and what goes in its notes.
public struct ReleasePlan: Equatable, Sendable {
    public let version: SemanticVersion
    public let previousTag: String?
    public let breaking: [ReleaseEntry]
    public let features: [ReleaseEntry]
    public let fixes: [ReleaseEntry]
    /// Subjects that are not conventional titles; they never reach the notes.
    public let ignored: [String]

    public init(
        version: SemanticVersion, previousTag: String?,
        breaking: [ReleaseEntry], features: [ReleaseEntry], fixes: [ReleaseEntry], ignored: [String]
    ) {
        self.version = version
        self.previousTag = previousTag
        self.breaking = breaking
        self.features = features
        self.fixes = fixes
        self.ignored = ignored
    }
}

/// Decides the next version and sorts commits into note sections.
public enum ReleasePlanner {
    /// Plans a release. The first release (`previousTag == nil`) is always
    /// 1.0.0. Otherwise the version is the previous one bumped by the highest
    /// bump among the commits; nil when nothing is releasable or the previous
    /// tag is not a version.
    public static func plan(commits: [ReleaseCommit], previousTag: String?) -> ReleasePlan? {
        var breaking: [ReleaseEntry] = []
        var features: [ReleaseEntry] = []
        var fixes: [ReleaseEntry] = []
        var ignored: [String] = []
        var bump = VersionBump.none

        for commit in commits {
            guard let title = ConventionalTitle(commit.subject) else {
                ignored.append(commit.subject)
                continue
            }
            let entry = makeEntry(title, body: commit.body)
            if title.isBreaking {
                breaking.append(entry)
                bump = max(bump, .major)
            } else if title.type == "feat" {
                features.append(entry)
                bump = max(bump, .minor)
            } else if title.type == "fix" || title.type == "perf" {
                fixes.append(entry)
                bump = max(bump, .patch)
            }
        }

        let version: SemanticVersion
        if let previousTag {
            guard let previous = SemanticVersion(tag: previousTag), bump != .none else { return nil }
            version = previous.bumped(bump)
        } else {
            version = SemanticVersion(major: 1, minor: 0, patch: 0)
        }
        return ReleasePlan(
            version: version, previousTag: previousTag,
            breaking: breaking, features: features, fixes: fixes, ignored: ignored
        )
    }

    /// Subjects that are not conventional titles, in order.
    public static func ignoredSubjects(in commits: [ReleaseCommit]) -> [String] {
        commits.map(\.subject).filter { ConventionalTitle($0) == nil }
    }

    private static func makeEntry(_ title: ConventionalTitle, body: String) -> ReleaseEntry {
        var text = title.description
        var pullRequest: Int?
        if let match = text.range(of: #" \(#(\d+)\)$"#, options: .regularExpression) {
            let digits = text[match].filter(\.isNumber)
            pullRequest = Int(digits)
            text.removeSubrange(match)
        }
        return ReleaseEntry(scope: title.scope, text: text, pullRequest: pullRequest, bullets: changesBullets(body))
    }

    /// The `- ` / `* ` lines under a `## Changes` line, up to the next `## `.
    private static func changesBullets(_ body: String) -> [String] {
        var inChanges = false
        var bullets: [String] = []
        for rawLine in body.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                inChanges = line == "## Changes"
            } else if inChanges, line.hasPrefix("- ") || line.hasPrefix("* ") {
                let bullet = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
                if !bullet.isEmpty { bullets.append(bullet) }
            }
        }
        return bullets
    }
}

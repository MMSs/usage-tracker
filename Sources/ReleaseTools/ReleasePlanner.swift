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

/// Why a release could not be planned.
public enum ReleasePlanError: Error, Equatable, CustomStringConvertible {
    /// The previous tag is not `vX.Y.Z`, so no next version can be derived.
    case previousTagIsNotAVersion(String)

    public var description: String {
        switch self {
        case let .previousTagIsNotAVersion(tag): "previous tag \"\(tag)\" is not vX.Y.Z"
        }
    }
}

/// Decides the next version and sorts commits into note sections.
public enum ReleasePlanner {
    /// Plans a release. The first release (`previousTag == nil`) is always
    /// 1.0.0. Otherwise the version is the previous one bumped by the highest
    /// bump among the commits; nil when nothing is releasable. Throws when the
    /// previous tag is not a version, so a wrong tag is never mistaken for
    /// "nothing to release".
    public static func plan(commits: [ReleaseCommit], previousTag: String?) throws -> ReleasePlan? {
        let previousVersion: SemanticVersion?
        if let previousTag {
            guard let parsed = SemanticVersion(tag: previousTag) else {
                throw ReleasePlanError.previousTagIsNotAVersion(previousTag)
            }
            previousVersion = parsed
        } else {
            previousVersion = nil
        }
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
        if let previousVersion {
            guard bump != .none else { return nil }
            version = previousVersion.bumped(bump)
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

    /// The `- ` / `* ` items under a `## Changes` line, up to the next `## `.
    /// As in Markdown, a line right after an item continues it (GitHub wraps
    /// squash-merge bodies that way); a blank line ends it.
    private static func changesBullets(_ body: String) -> [String] {
        var inChanges = false
        var inBullet = false
        var bullets: [String] = []
        for rawLine in body.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                inChanges = line == "## Changes"
                inBullet = false
            } else if !inChanges || line.isEmpty {
                inBullet = false
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                let bullet = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
                inBullet = !bullet.isEmpty
                if inBullet { bullets.append(bullet) }
            } else if inBullet {
                bullets[bullets.count - 1] += " " + line
            }
        }
        return bullets
    }
}

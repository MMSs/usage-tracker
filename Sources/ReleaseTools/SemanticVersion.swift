import Foundation

/// How far a set of changes moves the version, smallest first.
public enum VersionBump: Comparable, Sendable {
    case none, patch, minor, major
}

/// A `major.minor.patch` version, read from tags like `v1.2.3`.
public struct SemanticVersion: Comparable, CustomStringConvertible, Equatable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses `vX.Y.Z` only; pre-release suffixes and bare numbers are refused.
    public init?(tag: String) {
        guard tag.hasPrefix("v") else { return nil }
        let parts = tag.dropFirst().split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.map { part -> Int? in
            part.allSatisfy { $0.isASCII && $0.isNumber } ? Int(part) : nil
        }
        guard let major = numbers[0], let minor = numbers[1], let patch = numbers[2] else { return nil }
        self.init(major: major, minor: minor, patch: patch)
    }

    /// The version after `bump`: a major bump resets minor and patch, a minor
    /// bump resets patch.
    public func bumped(_ bump: VersionBump) -> SemanticVersion {
        switch bump {
        case .none: self
        case .patch: SemanticVersion(major: major, minor: minor, patch: patch + 1)
        case .minor: SemanticVersion(major: major, minor: minor + 1, patch: 0)
        case .major: SemanticVersion(major: major + 1, minor: 0, patch: 0)
        }
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

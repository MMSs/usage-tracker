import Testing
@testable import ReleaseTools

@Suite struct SemanticVersionTests {
    @Test func aVPrefixedTagParses() {
        let version = SemanticVersion(tag: "v1.2.3")
        #expect(version == SemanticVersion(major: 1, minor: 2, patch: 3))
        #expect(version?.description == "1.2.3")
    }

    @Test func otherShapesDoNotParse() {
        for bad in ["1.2.3", "v1.2", "v1.2.3-beta", "v1.2.3.4", "v1.a.3", ""] {
            #expect(SemanticVersion(tag: bad) == nil, "\(bad)")
        }
    }

    @Test func bumpingResetsTheLowerParts() {
        let version = SemanticVersion(major: 1, minor: 2, patch: 3)
        #expect(version.bumped(.major).description == "2.0.0")
        #expect(version.bumped(.minor).description == "1.3.0")
        #expect(version.bumped(.patch).description == "1.2.4")
        #expect(version.bumped(.none) == version)
    }

    @Test func versionsCompareNumerically() {
        #expect(SemanticVersion(major: 1, minor: 10, patch: 0) > SemanticVersion(major: 1, minor: 9, patch: 9))
    }

    @Test func bumpsOrderFromNoneToMajor() {
        #expect(VersionBump.none < .patch && VersionBump.patch < .minor && VersionBump.minor < .major)
    }
}

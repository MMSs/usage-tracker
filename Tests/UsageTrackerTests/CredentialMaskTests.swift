import Testing
@testable import UsageTracker

@Suite struct CredentialMaskTests {
    @Test func longValuesShowSixAndFour() throws {
        let mask = try #require(CredentialMask(value: "eyJhbGciOiJIUzI1NiJ9.k3Qw"))

        #expect(mask.prefix == "eyJhbG")
        #expect(mask.suffix == "k3Qw")
        #expect(mask.text(ellipsisCount: 3) == "eyJhbG………k3Qw")
    }

    @Test func shortValuesShowLess() throws {
        let medium = try #require(CredentialMask(value: "abcdefgh"))
        #expect(medium.prefix == "ab" && medium.suffix == "gh")

        let tiny = try #require(CredentialMask(value: "abc"))
        #expect(tiny.prefix == "" && tiny.suffix == "")
        #expect(tiny.text(ellipsisCount: 0) == "…")

        #expect(CredentialMask(value: "") == nil)
    }

    @Test func ellipsisCountFillsTheWidth() {
        #expect(CredentialMask.ellipsisCount(availableWidth: 70, ellipsisWidth: 7) == 10)
        #expect(CredentialMask.ellipsisCount(availableWidth: 69, ellipsisWidth: 7) == 9)
        #expect(CredentialMask.ellipsisCount(availableWidth: 0, ellipsisWidth: 7) == 1)
        #expect(CredentialMask.ellipsisCount(availableWidth: 70, ellipsisWidth: 0) == 1)
    }
}

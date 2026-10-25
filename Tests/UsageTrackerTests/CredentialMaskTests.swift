import Testing
@testable import UsageTracker

@Suite struct CredentialMaskTests {
    @Test func longValuesShowSixAndFour() throws {
        let mask = try #require(CredentialMask(value: "eyJhbGciOiJIUzI1NiJ9.k3Qw"))

        #expect(mask.prefix == "eyJhbG")
        #expect(mask.suffix == "k3Qw")
        #expect(mask.text(ellipsisCount: 3) == "eyJhbG………k3Qw")
    }

    @Test func aKindPrefixIsShownWholeThenTheRandomPart() throws {
        let session = try #require(CredentialMask(value: "sk-ant-sid01-AbCdEfGhIjKlMnOp"))
        let admin = try #require(CredentialMask(value: "sk-ant-admin01-QrStUvWxYz123456"))

        #expect(session.prefix == "sk-ant-sid01-AbCd" && session.suffix == "MnOp")
        #expect(admin.prefix == "sk-ant-admin01-QrSt" && admin.suffix == "3456")
    }

    @Test func otherVendorsKindPrefixesAreRecognised() throws {
        let openAI = try #require(CredentialMask(value: "sk-admin-Zx9Yw8Vu7Ts6Rq5P"))
        let cursor = try #require(CredentialMask(value: "user_01JABCDEFGH%3A%3AeyJhbGciOiJ.sig9"))
        let refresh = try #require(CredentialMask(value: "rt_Kp2Lq3Mr4Ns5Ot6"))

        #expect(openAI.prefix == "sk-admin-Zx9Y" && openAI.suffix == "Rq5P")
        #expect(cursor.prefix == "user_01JA" && cursor.suffix == "sig9")
        #expect(refresh.prefix == "rt_Kp2L" && refresh.suffix == "5Ot6")
    }

    @Test func aRandomSegmentAfterTheKindIsNotTakenForPartOfIt() throws {
        let mask = try #require(CredentialMask(value: "sk-ant-api03-k3qw-AbCdEfGhIjKl"))

        #expect(mask.prefix == "sk-ant-api03-k3qw")
    }

    @Test func aShortRandomPartFallsBackToTheWholeValue() throws {
        let mask = try #require(CredentialMask(value: "sk-ant-sid01-AbC"))

        #expect(mask.prefix == "sk-ant" && mask.suffix == "-AbC")
    }

    @Test func shortValuesShowLess() throws {
        let medium = try #require(CredentialMask(value: "abcdefgh"))
        #expect(medium.prefix == "ab" && medium.suffix == "gh")

        let tiny = try #require(CredentialMask(value: "abc"))
        #expect(tiny.prefix == "" && tiny.suffix == "")
        #expect(tiny.text(ellipsisCount: 0) == "…")

        #expect(CredentialMask(value: "") == nil)
    }

    @Test func whitespaceAndNewlinesAreSkipped() throws {
        let mask = try #require(CredentialMask(value: "{\n  \"tokens\": {\"access_token\": \"abc\"}\n}\n"))

        #expect(mask.prefix == "{\"toke")
        #expect(mask.suffix == "c\"}}")
        #expect(CredentialMask(value: " \n ") == nil)
    }

    @Test func ellipsisCountFillsTheWidth() {
        #expect(CredentialMask.ellipsisCount(availableWidth: 70, ellipsisWidth: 7) == 10)
        #expect(CredentialMask.ellipsisCount(availableWidth: 69, ellipsisWidth: 7) == 9)
        #expect(CredentialMask.ellipsisCount(availableWidth: 0, ellipsisWidth: 7) == 1)
        #expect(CredentialMask.ellipsisCount(availableWidth: 70, ellipsisWidth: 0) == 1)
    }
}

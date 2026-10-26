import Testing
@testable import ReleaseTools

@Suite struct ConventionalTitleTests {
    @Test func aPlainTitleParsesItsTypeAndDescription() {
        let title = ConventionalTitle("fix: a")
        #expect(title?.type == "fix")
        #expect(title?.scope == nil)
        #expect(title?.isBreaking == false)
        #expect(title?.description == "a")
    }

    @Test func aScopedBreakingTitleParsesAllParts() {
        let title = ConventionalTitle("feat(cursor)!: a")
        #expect(title?.type == "feat")
        #expect(title?.scope == "cursor")
        #expect(title?.isBreaking == true)
    }

    @Test func malformedTitlesAreRejected() {
        for bad in ["Fix: a", "fix:a", "fix a", "feature: a", "fix(): a", "fix: ", "fix(Bad): a"] {
            #expect(ConventionalTitle(bad) == nil, "\(bad)")
        }
    }

    @Test func shellMetacharactersAreKeptLiterally() {
        let text = "say \"$(rm -rf ~)\" and `id`"
        #expect(ConventionalTitle("fix: \(text)")?.description == text)
    }
}

import Testing
@testable import UsageTracker

@Suite struct CredentialFieldStateTests {
    @Test func blankDraftIsNotSavable() {
        var s = CredentialFieldState(isSaved: true)
        s.draft = "   \n"
        #expect(!s.hasSavableChange)
    }

    @Test func draftIsTrimmed() {
        var s = CredentialFieldState(isSaved: false)
        s.draft = "  abc\n"
        #expect(s.trimmedDraft == "abc")
        #expect(s.hasSavableChange)
    }

    @Test func markSavedClearsDraft() {
        var s = CredentialFieldState(isSaved: false)
        s.draft = "x"
        s.markSaved()
        #expect(s.draft == "")
        #expect(s.isSaved)
    }

    @Test func markRemovedClearsSavedFlag() {
        var s = CredentialFieldState(isSaved: true)
        s.draft = "x"
        s.markRemoved()
        #expect(s.draft == "")
        #expect(!s.isSaved)
    }
}

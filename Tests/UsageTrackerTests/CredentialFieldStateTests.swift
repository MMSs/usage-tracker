import Testing
@testable import UsageTracker

@Suite struct CredentialFieldStateTests {
    @Test func blankDraftIsNotSavable() {
        var s = CredentialFieldState(mask: CredentialMask(value: "abcdefghijklmnop"))
        s.draft = "   \n"
        #expect(!s.hasSavableChange)
    }

    @Test func draftIsTrimmed() {
        var s = CredentialFieldState(mask: nil)
        s.draft = "  abc\n"
        #expect(s.trimmedDraft == "abc")
        #expect(s.hasSavableChange)
    }

    @Test func markSavedClearsDraft() {
        var s = CredentialFieldState(mask: nil)
        s.draft = "x"
        s.markSaved(mask: CredentialMask(value: "abcdefghijklmnop"))
        #expect(s.draft == "")
        #expect(s.isSaved)
        #expect(s.mask?.prefix == "abcdef")
    }

    @Test func markRemovedClearsSavedFlag() {
        var s = CredentialFieldState(mask: CredentialMask(value: "abcdefghijklmnop"))
        s.draft = "x"
        s.markRemoved()
        #expect(s.draft == "")
        #expect(!s.isSaved)
    }
}

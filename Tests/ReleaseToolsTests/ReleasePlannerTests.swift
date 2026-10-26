import Testing
@testable import ReleaseTools

@Suite struct ReleasePlannerTests {
    private func commit(_ subject: String, _ body: String = "") -> ReleaseCommit {
        ReleaseCommit(subject: subject, body: body)
    }

    @Test func parsingSplitsRecordsAndFieldsAndKeepsMultiLineBodies() {
        let text = "fix: a (#1)\u{1F}line one\nline two\n\u{1E}\nfeat: b\u{1F}\u{1E}\n"
        #expect(ReleaseCommit.parseLog(text) == [
            ReleaseCommit(subject: "fix: a (#1)", body: "line one\nline two"),
            ReleaseCommit(subject: "feat: b", body: ""),
        ])
    }

    @Test func aTrailingSeparatorAddsNoRecord() {
        #expect(ReleaseCommit.parseLog("fix: a\u{1F}\u{1E}").count == 1)
        #expect(ReleaseCommit.parseLog("").isEmpty)
    }

    @Test func theFirstReleaseIsAlwaysOneOhOh() {
        let plan = ReleasePlanner.plan(commits: [commit("docs: x")], previousTag: nil)
        #expect(plan?.version.description == "1.0.0")
        #expect(plan?.previousTag == nil)
        #expect(ReleasePlanner.plan(commits: [], previousTag: nil)?.version.description == "1.0.0")
    }

    @Test func aFeatureAndAFixBumpTheMinorVersion() {
        let plan = ReleasePlanner.plan(commits: [commit("fix: a"), commit("feat: b")], previousTag: "v1.2.3")
        #expect(plan?.version.description == "1.3.0")
        #expect(plan?.previousTag == "v1.2.3")
    }

    @Test func aFixAndAPerfBumpThePatchVersion() {
        let plan = ReleasePlanner.plan(commits: [commit("perf: a"), commit("fix: b")], previousTag: "v1.2.3")
        #expect(plan?.version.description == "1.2.4")
    }

    @Test func docsOnlyChangesReleaseNothing() {
        #expect(ReleasePlanner.plan(commits: [commit("docs: a"), commit("chore: b")], previousTag: "v1.2.3") == nil)
    }

    @Test func aBreakingFixBumpsTheMajorVersion() {
        let plan = ReleasePlanner.plan(commits: [commit("fix!: a")], previousTag: "v1.2.3")
        #expect(plan?.version.description == "2.0.0")
        #expect(plan?.breaking.map(\.text) == ["a"])
        #expect(plan?.fixes.isEmpty == true)
    }

    @Test func anUnparseableSubjectIsIgnoredAndLeftOutOfTheNotes() {
        let plan = ReleasePlanner.plan(commits: [commit("tidy things"), commit("fix: a")], previousTag: "v1.0.0")
        #expect(plan?.ignored == ["tidy things"])
        #expect(plan?.fixes.map(\.text) == ["a"])
        #expect(plan?.features.isEmpty == true)
    }

    @Test func aPullRequestSuffixMovesIntoThePullRequestNumber() {
        let plan = ReleasePlanner.plan(commits: [commit("fix(ui): a thing (#42)")], previousTag: "v1.0.0")
        #expect(plan?.fixes == [ReleaseEntry(scope: "ui", text: "a thing", pullRequest: 42, bullets: [])])
    }

    @Test func changesBulletsAreCapturedButLaterSectionsAreNot() {
        let body = """
        ## Summary
        - not this

        ## Changes
        - first
        * second
        not a bullet

        ## Test plan
        - nor this
        """
        let plan = ReleasePlanner.plan(commits: [commit("feat: a (#7)", body)], previousTag: "v1.0.0")
        #expect(plan?.features.first?.bullets == ["first", "second"])
    }

    @Test func entriesStayOldestFirst() {
        let plan = ReleasePlanner.plan(commits: [commit("fix: one"), commit("fix: two")], previousTag: "v1.0.0")
        #expect(plan?.fixes.map(\.text) == ["one", "two"])
    }

    @Test func aNonVersionPreviousTagReleasesNothing() {
        #expect(ReleasePlanner.plan(commits: [commit("feat: a")], previousTag: "nightly") == nil)
    }
}

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

    @Test func theFirstReleaseIsAlwaysOneOhOh() throws {
        let plan = try ReleasePlanner.plan(commits: [commit("docs: x")], previousTag: nil)
        #expect(plan?.version.description == "1.0.0")
        #expect(plan?.previousTag == nil)
        #expect(try ReleasePlanner.plan(commits: [], previousTag: nil)?.version.description == "1.0.0")
    }

    @Test func aFeatureAndAFixBumpTheMinorVersion() throws {
        let plan = try ReleasePlanner.plan(commits: [commit("fix: a"), commit("feat: b")], previousTag: "v1.2.3")
        #expect(plan?.version.description == "1.3.0")
        #expect(plan?.previousTag == "v1.2.3")
    }

    @Test func aFixAndAPerfBumpThePatchVersion() throws {
        let plan = try ReleasePlanner.plan(commits: [commit("perf: a"), commit("fix: b")], previousTag: "v1.2.3")
        #expect(plan?.version.description == "1.2.4")
    }

    @Test func docsOnlyChangesReleaseNothing() throws {
        #expect(try ReleasePlanner.plan(commits: [commit("docs: a"), commit("chore: b")], previousTag: "v1.2.3") == nil)
    }

    @Test func aBreakingFixBumpsTheMajorVersion() throws {
        let plan = try ReleasePlanner.plan(commits: [commit("fix!: a")], previousTag: "v1.2.3")
        #expect(plan?.version.description == "2.0.0")
        #expect(plan?.breaking.map(\.text) == ["a"])
        #expect(plan?.fixes.isEmpty == true)
    }

    @Test func anUnparseableSubjectIsIgnoredAndLeftOutOfTheNotes() throws {
        let plan = try ReleasePlanner.plan(commits: [commit("tidy things"), commit("fix: a")], previousTag: "v1.0.0")
        #expect(plan?.ignored == ["tidy things"])
        #expect(plan?.fixes.map(\.text) == ["a"])
        #expect(plan?.features.isEmpty == true)
    }

    @Test func aPullRequestSuffixMovesIntoThePullRequestNumber() throws {
        let plan = try ReleasePlanner.plan(commits: [commit("fix(ui): a thing (#42)")], previousTag: "v1.0.0")
        #expect(plan?.fixes == [ReleaseEntry(scope: "ui", text: "a thing", pullRequest: 42, bullets: [])])
    }

    @Test func changesBulletsAreCapturedButLaterSectionsAreNot() throws {
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
        let plan = try ReleasePlanner.plan(commits: [commit("feat: a (#7)", body)], previousTag: "v1.0.0")
        #expect(plan?.features.first?.bullets == ["first", "second"])
    }

    /// GitHub wraps a squash-merge body at about 72 columns without indenting the
    /// continuation, so a line right after a bullet carries on that bullet.
    @Test func aBulletWrappedOntoTheNextLinesStaysWhole() throws {
        let body = """
        ## Changes

        - A card under it lists the providers with a custom appearance, in menu
        bar order. A name opens that provider's Appearance section.
        - Short.

        Closing paragraph.
        """
        let plan = try ReleasePlanner.plan(commits: [commit("feat: a (#7)", body)], previousTag: "v1.0.0")
        #expect(plan?.features.first?.bullets == [
            "A card under it lists the providers with a custom appearance, in menu bar order. A name opens that provider's Appearance section.",
            "Short.",
        ])
    }

    @Test func entriesStayOldestFirst() throws {
        let plan = try ReleasePlanner.plan(commits: [commit("fix: one"), commit("fix: two")], previousTag: "v1.0.0")
        #expect(plan?.fixes.map(\.text) == ["one", "two"])
    }

    @Test func aPreviousTagThatIsNotAVersionFailsInsteadOfReleasingNothing() throws {
        for tag in ["nightly", "1.2.0", "v1.2"] {
            #expect(throws: ReleasePlanError.previousTagIsNotAVersion(tag)) {
                try ReleasePlanner.plan(commits: [commit("feat: a")], previousTag: tag)
            }
        }
    }
}

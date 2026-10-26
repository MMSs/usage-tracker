import Testing
@testable import ReleaseTools

@Suite struct ReleaseNotesRendererTests {
    private let repository = "MMSs/usage-tracker"

    private func entry(_ text: String, scope: String? = nil, pr: Int? = nil, bullets: [String] = []) -> ReleaseEntry {
        ReleaseEntry(scope: scope, text: text, pullRequest: pr, bullets: bullets)
    }

    private var plan: ReleasePlan {
        ReleasePlan(
            version: SemanticVersion(major: 2, minor: 0, patch: 0),
            previousTag: "v1.1.0",
            breaking: [entry("drop the old store", pr: 40)],
            features: [
                entry("add an updates section to settings", pr: 41),
                entry("show the team plan's pooled limit", scope: "cursor", pr: 43, bullets: ["bullet one", "another bullet"]),
            ],
            fixes: [entry("keep one popover's fade-out from cancelling another's", pr: 42)],
            ignored: []
        )
    }

    @Test func markdownMatchesTheDesignedLayout() {
        let expected = """
        ## 2.0.0

        ### Breaking changes
        - drop the old store ([#40](https://github.com/MMSs/usage-tracker/pull/40))

        ### Features
        - add an updates section to settings ([#41](https://github.com/MMSs/usage-tracker/pull/41))
        - **cursor:** show the team plan's pooled limit ([#43](https://github.com/MMSs/usage-tracker/pull/43))
          - bullet one
          - another bullet

        ### Fixes
        - keep one popover's fade-out from cancelling another's ([#42](https://github.com/MMSs/usage-tracker/pull/42))

        **Full changelog:** https://github.com/MMSs/usage-tracker/compare/v1.1.0...v2.0.0

        """
        #expect(ReleaseNotesRenderer.markdown(plan, repository: repository, firstReleaseSummary: nil) == expected)
    }

    @Test func emptySectionsAreLeftOut() {
        let only = ReleasePlan(
            version: SemanticVersion(major: 1, minor: 0, patch: 1), previousTag: "v1.0.0",
            breaking: [], features: [], fixes: [entry("a")], ignored: []
        )
        let text = ReleaseNotesRenderer.markdown(only, repository: repository, firstReleaseSummary: nil)
        #expect(!text.contains("Breaking") && !text.contains("Features"))
        #expect(text.contains("### Fixes"))
    }

    @Test func theFirstReleaseIsJustTheSummary() {
        let first = ReleasePlan(
            version: SemanticVersion(major: 1, minor: 0, patch: 0), previousTag: nil,
            breaking: [], features: [entry("x")], fixes: [], ignored: []
        )
        #expect(ReleaseNotesRenderer.markdown(first, repository: repository, firstReleaseSummary: "Hello.")
            == "## 1.0.0\n\nHello.")
        #expect(ReleaseNotesRenderer.html(first, repository: repository, firstReleaseSummary: "One.\n\nTwo & three.")
            == "<p>One.</p>\n<p>Two &amp; three.</p>\n")
    }

    @Test func htmlRendersSectionsWithoutAVersionHeading() {
        let html = ReleaseNotesRenderer.html(plan, repository: repository, firstReleaseSummary: nil)
        #expect(!html.contains("2.0.0</h"))
        #expect(html.contains("<h3>Features</h3>"))
        #expect(html.contains("<li><strong>cursor:</strong> show the team plan&#39;s pooled limit"))
        #expect(html.contains("<li>bullet one</li>"))
        #expect(html.contains("href=\"https://github.com/MMSs/usage-tracker/pull/43\""))
    }

    @Test func htmlEscapesEveryPieceOfText() {
        let nasty = ReleasePlan(
            version: SemanticVersion(major: 1, minor: 0, patch: 1), previousTag: "v1.0.0",
            breaking: [], features: [], fixes: [entry("show <b> & \"quotes\" ]]>", bullets: ["<i>"])], ignored: []
        )
        let html = ReleaseNotesRenderer.html(nasty, repository: repository, firstReleaseSummary: nil)
        #expect(html.contains("show &lt;b&gt; &amp; &quot;quotes&quot; ]]&gt;"))
        #expect(html.contains("&lt;i&gt;"))
        #expect(!html.contains("<b>"))
    }
}

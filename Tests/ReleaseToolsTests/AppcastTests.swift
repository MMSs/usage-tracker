import Foundation
import Testing
@testable import ReleaseTools

@Suite struct AppcastTests {
    private let published = Date(timeIntervalSince1970: 1_792_000_000) // 2026-10-14 17:46:40 GMT

    private func xml(notes: String = "<p>Hi</p>") -> String {
        Appcast.xml(
            version: SemanticVersion(major: 1, minor: 2, patch: 3),
            url: URL(string: "https://example.com/a.zip?x=1&y=2")!,
            length: 1234,
            edSignature: "sig+/=\"",
            notesHTML: notes,
            published: published,
            minimumSystemVersion: "26.0"
        )
    }

    private func parse(_ text: String) throws -> XMLDocument {
        try XMLDocument(xmlString: text, options: [])
    }

    @Test func theFeedParsesAndCarriesTheVersionAndEnclosure() throws {
        let doc = try parse(xml())
        let version = try doc.nodes(forXPath: "//item/*[local-name()='version']").first?.stringValue
        let short = try doc.nodes(forXPath: "//item/*[local-name()='shortVersionString']").first?.stringValue
        let minimum = try doc.nodes(forXPath: "//item/*[local-name()='minimumSystemVersion']").first?.stringValue
        #expect(version == "1.2.3" && short == "1.2.3" && minimum == "26.0")
        #expect(try doc.nodes(forXPath: "//channel/title").first?.stringValue == "Usage Tracker")

        let enclosure = try #require(doc.nodes(forXPath: "//item/enclosure").first as? XMLElement)
        #expect(enclosure.attribute(forName: "url")?.stringValue == "https://example.com/a.zip?x=1&y=2")
        #expect(enclosure.attribute(forName: "length")?.stringValue == "1234")
        #expect(enclosure.attribute(forName: "type")?.stringValue == "application/octet-stream")
        #expect(enclosure.attribute(forName: "sparkle:edSignature")?.stringValue == "sig+/=\"")
    }

    @Test func thePublicationDateIsRFC822InGMT() throws {
        let doc = try parse(xml())
        #expect(try doc.nodes(forXPath: "//item/pubDate").first?.stringValue == "Wed, 14 Oct 2026 17:46:40 +0000")
    }

    @Test func notesContainingACDATAEndStillRoundTrip() throws {
        let notes = "<p>a ]]> b</p>"
        let doc = try parse(xml(notes: notes))
        #expect(try doc.nodes(forXPath: "//item/description").first?.stringValue == notes)
    }
}

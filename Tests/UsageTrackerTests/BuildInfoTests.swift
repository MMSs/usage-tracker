import Foundation
import Testing
@testable import UsageTracker

@Suite struct BuildInfoTests {
    @Test func readsVersionAndFeed() {
        let feed = "https://github.com/MMSs/usage-tracker/releases/latest/download/appcast.xml"
        let info = BuildInfo(infoDictionary: [
            "CFBundleShortVersionString": "1.0.0",
            "SUFeedURL": feed,
        ])
        #expect(info.version == "1.0.0")
        #expect(info.feedURL?.absoluteString == feed)
        #expect(info.versionText == "Version 1.0.0")
    }

    @Test func aSourceBuildHasNoVersionOrFeed() {
        for info in [BuildInfo(infoDictionary: [:]), BuildInfo(infoDictionary: nil)] {
            #expect(info.version == nil)
            #expect(info.feedURL == nil)
            #expect(info.versionText == "Version dev")
        }
    }

    @Test func anEmptyFeedIsNoFeed() {
        #expect(BuildInfo(infoDictionary: ["SUFeedURL": ""]).feedURL == nil)
    }
}

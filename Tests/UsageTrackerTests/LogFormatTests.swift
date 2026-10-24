import Foundation
import Testing
@testable import UsageTracker

@Suite struct LogFormatTests {
    @Test func onlyTheBundledAppLogsIntoItsOwnSubsystem() {
        #expect(Log.subsystem(forBundleIdentifier: AppIdentity.bundleID) == "com.mohabsam.usage-tracker")
        #expect(Log.subsystem(forBundleIdentifier: nil) == "com.mohabsam.usage-tracker.unbundled")
        #expect(Log.subsystem(forBundleIdentifier: "com.apple.dt.xctest.tool") == "com.mohabsam.usage-tracker.unbundled")
    }

    @Test func testRunsLogOutsideTheAppSubsystem() {
        #expect(Log.subsystem != AppIdentity.bundleID)
    }

    @Test func endpointDropsTheQueryAndRedactsUUIDs() {
        let url = URL(string: "https://claude.ai/api/organizations/0F1E2D3C-4B5A-6978-8A9B-0C1D2E3F4A5B/usage?token=abc")!
        #expect(LogFormat.endpoint(url) == "claude.ai/api/organizations/{uuid}/usage")
    }

    @Test func endpointKeepsPlainPaths() {
        let url = URL(string: "https://api.anthropic.com/v1/organizations/cost_report?starting_at=2026-10-01T00:00:00Z&page=xyz")!
        #expect(LogFormat.endpoint(url) == "api.anthropic.com/v1/organizations/cost_report")
    }

    @Test func endpointWithoutAURL() {
        #expect(LogFormat.endpoint(nil) == "?")
    }

    @Test func decodingSummaryNamesTheKindAndPath() {
        struct Bucket: Decodable { let amount: String }
        struct Page: Decodable { let data: [Bucket] }

        do {
            _ = try JSONDecoder().decode(Page.self, from: Data(#"{"data":[{"amount":"1"},{"amount":2.5}]}"#.utf8))
            Issue.record("expected a decoding error")
        } catch {
            #expect(LogFormat.decodingSummary(error) == "type mismatch at data[1].amount")
        }

        do {
            _ = try JSONDecoder().decode(Page.self, from: Data(#"{"data":[{}]}"#.utf8))
            Issue.record("expected a decoding error")
        } catch {
            #expect(LogFormat.decodingSummary(error) == "missing key amount at data[0]")
        }

        do {
            _ = try JSONDecoder().decode(Page.self, from: Data("<html>".utf8))
            Issue.record("expected a decoding error")
        } catch {
            #expect(LogFormat.decodingSummary(error) == "corrupted data at root")
        }
    }

    @Test func decodingSummaryOfOtherErrorsIsTheTypeName() {
        struct Odd: Error {}
        #expect(LogFormat.decodingSummary(Odd()) == "Odd")
    }
}

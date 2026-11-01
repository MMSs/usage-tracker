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

    @Test func errorSummaryReadsTheServersExplanation() {
        let envelope = #"{"type":"error","error":{"type":"invalid_request_error","message":"Invalid date range: ending date must be after starting date"},"request_id":"req_1"}"#
        #expect(LogFormat.errorSummary(Data(envelope.utf8)) == "invalid_request_error: Invalid date range: ending date must be after starting date")
        #expect(LogFormat.errorSummary(Data(#"{"detail":"Not Found"}"#.utf8)) == "Not Found")
        #expect(LogFormat.errorSummary(Data(#"{"message":"Too Many Requests"}"#.utf8)) == "Too Many Requests")
        #expect(LogFormat.errorSummary(Data(#"{"error":"bad"}"#.utf8)) == "bad")
        #expect(LogFormat.errorSummary(Data("<!DOCTYPE html>".utf8)) == nil)
        #expect(LogFormat.errorSummary(Data(#"{"ok":true}"#.utf8)) == nil)
        #expect(LogFormat.errorSummary(Data()) == nil)
    }

    @Test func errorSummaryIsCutShort() {
        let long = String(repeating: "x", count: 300)
        let summary = LogFormat.errorSummary(Data(#"{"message":"\#(long)"}"#.utf8))

        #expect(summary?.count == 201)
        #expect(summary?.hasSuffix("…") == true)
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

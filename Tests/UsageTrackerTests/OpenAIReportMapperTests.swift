import Foundation
import Testing
@testable import UsageTracker

struct OpenAIReportMapperTests {
    private typealias Window = OpenAIUsageResponse.Window

    private let now = Date(timeIntervalSince1970: 1_792_800_000)
    private let reset = Date(timeIntervalSince1970: 1_792_890_000)

    private func window(_ seconds: Int?, percent: Double? = 10, resetAt: Date? = nil) -> Window {
        Window(usedPercent: percent, windowSeconds: seconds, resetAt: resetAt ?? reset)
    }

    private func usage(
        planType: String? = "plus",
        primary: Window? = nil,
        secondary: Window? = nil,
        additional: [OpenAIUsageResponse.AdditionalLimit] = [],
        credits: OpenAIUsageResponse.Credits? = nil
    ) -> OpenAIUsageResponse {
        OpenAIUsageResponse(planType: planType, primary: primary, secondary: secondary, additional: additional, credits: credits)
    }

    private func map(_ usage: OpenAIUsageResponse) -> ProviderReport {
        OpenAIReportMapper.subscription(usage, now: now)
    }

    @Test func sessionAndWeeklyCarryTheirLengths() {
        let report = map(usage(primary: window(18000, percent: 41), secondary: window(604_800, percent: 70)))

        #expect(report.planName == "Plus")
        #expect(report.spend == nil)
        #expect(report.windows == [
            LimitWindow(id: "session", label: "Session", percentUsed: 41, resetsAt: reset, parentID: nil, windowLength: 18000),
            LimitWindow(id: "weekly", label: "Weekly", percentUsed: 70, resetsAt: reset, parentID: nil, windowLength: 604_800),
        ])
    }

    @Test func windowsAreClassifiedByLengthNotPosition() throws {
        let url = try #require(Bundle.module.url(forResource: "openai-wham-usage-additional", withExtension: "json", subdirectory: "Fixtures"))
        let response = try JSONDecoder().decode(OpenAIUsageResponse.self, from: Data(contentsOf: url))

        let report = map(response)

        #expect(report.topLevelWindows.map(\.id) == ["session", "weekly"])
        #expect(report.windows.first?.percentUsed == 12)
        #expect(report.windows.first { $0.id == "weekly" }?.percentUsed == 55)
    }

    @Test func duplicateLengthsGetDistinctIDs() {
        let report = map(usage(primary: window(18000, percent: 1), secondary: window(18000, percent: 2)))

        #expect(report.windows.map(\.id) == ["session", "session:2"])
        #expect(report.windows.map(\.percentUsed) == [1, 2])
    }

    @Test func unknownLengthsGetHumanLabels() {
        let report = map(usage(
            primary: window(900),
            secondary: window(3600),
            additional: [.init(name: "extra", primary: window(172_800), secondary: window(0))]
        ))

        #expect(report.windows.map(\.id) == ["window:900", "window:3600"])
        #expect(report.windows.map(\.label) == ["15 minutes", "1 hour"])

        let days = map(usage(primary: window(172_800), secondary: window(-5)))
        #expect(days.windows.map(\.id) == ["window:172800"])
        #expect(days.windows.map(\.label) == ["2 days"])
        #expect(map(usage(primary: window(nil))).windows.isEmpty)
    }

    @Test func pastResetIsClosed() {
        let past = now.addingTimeInterval(-1)
        let report = map(usage(primary: window(18000, resetAt: past), secondary: window(604_800, resetAt: now)))

        #expect(report.windows.map(\.resetsAt) == [nil, nil])
        #expect(report.windows.map(\.isOpen) == [false, false])
    }

    @Test func additionalLimitsBecomeChildrenOfTheMatchingWindow() {
        let report = map(usage(
            primary: window(18000),
            secondary: window(604_800),
            additional: [.init(name: "codex_other", primary: window(604_800, percent: 30), secondary: nil)]
        ))

        #expect(report.windows.map(\.id) == ["session", "weekly", "weekly:codex_other"])
        #expect(report.windows[2] == LimitWindow(
            id: "weekly:codex_other",
            label: "Codex other",
            percentUsed: 30,
            resetsAt: reset,
            parentID: "weekly",
            windowLength: 604_800
        ))
        #expect(report.children(of: "weekly").count == 1)
    }

    @Test func additionalLimitsWithoutAParentAreDropped() {
        let report = map(usage(
            primary: window(18000),
            additional: [.init(name: "codex_other", primary: window(604_800), secondary: window(3600))]
        ))

        #expect(report.windows.map(\.id) == ["session"])
    }

    @Test func creditsRowOnlyWhenGrantedAndLimited() {
        func extras(_ credits: OpenAIUsageResponse.Credits?) -> [MoneyRow] {
            map(usage(credits: credits)).extras
        }

        #expect(extras(.init(hasCredits: true, unlimited: false, balance: 12.5)) == [
            MoneyRow(id: "credits", label: "Credits", amount: 12.5, limit: nil),
        ])
        #expect(extras(.init(hasCredits: false, unlimited: false, balance: 12.5)).isEmpty)
        #expect(extras(.init(hasCredits: true, unlimited: true, balance: 12.5)).isEmpty)
        #expect(extras(.init(hasCredits: true, unlimited: false, balance: nil)).isEmpty)
        #expect(extras(nil).isEmpty)
    }

    @Test func planNamesAreTitled() {
        let known = ["plus", "pro", "team", "business", "enterprise", "edu", "free"]

        #expect(known.map { OpenAIReportMapper.planName($0) } == ["Plus", "Pro", "Team", "Business", "Enterprise", "Edu", "Free"])
        #expect(OpenAIReportMapper.planName("prolite") == "Prolite")
        #expect(OpenAIReportMapper.planName("") == nil)
        #expect(OpenAIReportMapper.planName("  ") == nil)
        #expect(OpenAIReportMapper.planName(nil) == nil)
    }
}

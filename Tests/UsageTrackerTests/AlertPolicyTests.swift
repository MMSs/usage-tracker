import Foundation
import Testing

@testable import UsageTracker

struct AlertPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_792_900_000)
    private let anthropic = ProviderRegistry.descriptor(for: .anthropic)

    private func iso(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)!
    }

    private func report(windows: [LimitWindow], spend: SpendPeriod? = nil) -> ProviderReport {
        ProviderReport(planName: nil, windows: windows, extras: [], spend: spend)
    }

    private func detail(_ resetsAt: Date, style: CountdownFormatter.ResetStyle) -> String {
        let text = CountdownFormatter.resetText(resetsAt: resetsAt, now: now, style: style)!

        return text.prefix(1).uppercased() + text.dropFirst() + "."
    }

    @Test func everyOpenWindowIsMeasured() {
        let sessionReset = iso("2026-10-27T08:00:00Z")
        let weeklyReset = iso("2026-10-30T08:00:00Z")
        let windows = [
            LimitWindow(id: "session", label: "Session", percentUsed: 82, resetsAt: sessionReset, parentID: nil),
            LimitWindow(id: "weekly", label: "Weekly", percentUsed: 40, resetsAt: weeklyReset, parentID: nil),
            LimitWindow(id: "weekly:fable", label: "Fable", percentUsed: 96, resetsAt: weeklyReset, parentID: "weekly"),
        ]

        let measures = AlertPolicy.measures(
            descriptor: anthropic, half: .subscription, report: report(windows: windows), budget: nil, now: now
        )

        let sessionMinutes = Int((sessionReset.timeIntervalSince1970 / 60).rounded())
        let weeklyMinutes = Int((weeklyReset.timeIntervalSince1970 / 60).rounded())
        #expect(measures.map(\.id) == [
            "anthropic.session.\(sessionMinutes)",
            "anthropic.weekly.\(weeklyMinutes)",
            "anthropic.weekly:fable.\(weeklyMinutes)",
        ])
        #expect(measures.map(\.subject) == ["Anthropic session", "Anthropic weekly", "Anthropic weekly · Fable"])
        #expect(measures.map(\.percent) == [82, 40, 96])
        #expect(measures.map(\.detail) == [
            detail(sessionReset, style: .session),
            detail(weeklyReset, style: .long),
            detail(weeklyReset, style: .long),
        ])
    }

    @Test func closedWindowsAreNotMeasured() {
        let windows = [LimitWindow(id: "session", label: "Session", percentUsed: 90, resetsAt: nil, parentID: nil)]

        #expect(AlertPolicy.measures(
            descriptor: anthropic, half: .subscription, report: report(windows: windows), budget: nil, now: now
        ).isEmpty)
    }

    @Test func aResetJitteringWithinAMinuteKeepsTheSameKey() {
        func id(_ text: String) -> String? {
            let windows = [LimitWindow(id: "session", label: "Session", percentUsed: 90, resetsAt: iso(text), parentID: nil)]

            return AlertPolicy.measures(
                descriptor: anthropic, half: .subscription, report: report(windows: windows), budget: nil, now: now
            ).first?.id
        }

        let first = id("2026-10-27T16:59:59.862Z")

        #expect(first != nil)
        #expect(first == id("2026-10-27T17:00:00.100Z"))
    }

    @Test func apiSpendIsMeasuredAgainstItsBudget() {
        let openai = ProviderRegistry.descriptor(for: .openai)
        let start = iso("2026-10-01T00:00:00Z")
        let spend = SpendPeriod(
            period: CyclePeriod(start: start, end: iso("2026-11-01T00:00:00Z")),
            spent: 8.2, limit: nil, unit: .dollars, daily: []
        )

        let measures = AlertPolicy.measures(
            descriptor: openai, half: .api, report: report(windows: [], spend: spend), budget: 10, now: now
        )

        #expect(measures == [
            AlertMeasure(
                id: "openai.api.\(Int(start.timeIntervalSince1970))",
                percent: 82,
                subject: "OpenAI API spend",
                detail: "\(BudgetUnit.dollars.format(8.2)) of \(BudgetUnit.dollars.format(10)) budget this month."
            ),
        ])
        #expect(measures.first?.detail == "$8.20 of $10.00 budget this month.")
    }

    @Test func noBudgetOrZeroBudgetMeansNoSpendMeasure() {
        let openai = ProviderRegistry.descriptor(for: .openai)
        let spend = SpendPeriod(
            period: CyclePeriod(start: iso("2026-10-01T00:00:00Z"), end: iso("2026-11-01T00:00:00Z")),
            spent: 8.2, limit: nil, unit: .dollars, daily: []
        )
        let apiReport = report(windows: [], spend: spend)

        #expect(AlertPolicy.measures(descriptor: openai, half: .api, report: apiReport, budget: nil, now: now).isEmpty)
        #expect(AlertPolicy.measures(descriptor: openai, half: .api, report: apiReport, budget: 0, now: now).isEmpty)
    }

    @Test func subscriptionSpendIsNotMeasured() {
        let cursor = ProviderRegistry.descriptor(for: .cursor)
        let spend = SpendPeriod(
            period: CyclePeriod(start: iso("2026-10-01T00:00:00Z"), end: iso("2026-11-01T00:00:00Z")),
            spent: 90, limit: 100, unit: .dollars, daily: []
        )

        #expect(AlertPolicy.measures(
            descriptor: cursor, half: .subscription, report: report(windows: [], spend: spend), budget: 100, now: now
        ).isEmpty)
    }

    @Test func alertTextNamesSubjectAndPercent() {
        let measure = AlertMeasure(
            id: "anthropic.weekly:fable.123", percent: 96.9, subject: "Anthropic weekly · Fable", detail: "Resets soon."
        )

        let alert = AlertPolicy.alert(for: measure, threshold: 95)

        #expect(alert == UsageAlert(key: "anthropic.weekly:fable.123.95", title: "Anthropic weekly · Fable at 96%", body: "Resets soon."))
    }

    // MARK: Session end

    private func window(resetsAt: Date?) -> LimitWindow {
        LimitWindow(id: "session", label: "Session", percentUsed: 10, resetsAt: resetsAt, parentID: nil)
    }

    @Test func aSessionPastItsResetHasEnded() {
        let reset = now.addingTimeInterval(-30)

        #expect(SessionEnd.ended(previousResetsAt: reset, current: window(resetsAt: nil), now: now) == reset)
        #expect(SessionEnd.ended(previousResetsAt: reset, current: nil, now: now) == reset)
    }

    @Test func aNewWindowFiveHoursLaterMeansTheSessionEnded() {
        let reset = now.addingTimeInterval(600)
        let current = window(resetsAt: reset.addingTimeInterval(5 * 3600))

        #expect(SessionEnd.ended(previousResetsAt: reset, current: current, now: now) == reset)
    }

    @Test func theSameWindowHasNotEnded() {
        let reset = now.addingTimeInterval(600)

        #expect(SessionEnd.ended(previousResetsAt: reset, current: window(resetsAt: reset), now: now) == nil)
    }

    @Test func noPreviousSessionNeverEnds() {
        #expect(SessionEnd.ended(previousResetsAt: nil, current: window(resetsAt: now.addingTimeInterval(3600)), now: now) == nil)
        #expect(SessionEnd.ended(previousResetsAt: nil, current: nil, now: now) == nil)
    }

    @Test func resetJitterUnderAMinuteIsTheSameSession() {
        let reset = now.addingTimeInterval(600)
        let current = window(resetsAt: reset.addingTimeInterval(59))

        #expect(SessionEnd.ended(previousResetsAt: reset, current: current, now: now) == nil)
    }

    @Test func theSessionAlertSaysBackToZeroOrNewSession() {
        let endedAt = iso("2026-10-27T08:00:00Z")
        let minutes = Int((endedAt.timeIntervalSince1970 / 60).rounded())

        let plain = AlertPolicy.sessionAlert(displayName: "Anthropic", endedAt: endedAt, newSessionStarted: false, provider: .anthropic)
        let started = AlertPolicy.sessionAlert(displayName: "Anthropic", endedAt: endedAt, newSessionStarted: true, provider: .anthropic)

        #expect(plain == UsageAlert(key: "anthropic.session.\(minutes)", title: "Anthropic session reset", body: "You're back to 0%."))
        #expect(started == UsageAlert(key: "anthropic.session.\(minutes)", title: "Anthropic session reset", body: "New session started."))
    }

    @Test func offlineNeverAlertsButEveryOtherCauseDoes() {
        let others: [RefreshFailure] = [
            .transport, .challenge, .unauthorized, .httpStatus(500), .rateLimited(until: nil), .decoding, .keychain,
            .needsOrganization, .unexpected,
        ]

        #expect(!RefreshFailure.offline.alertsAsFailure)
        #expect(others.allSatisfy { $0.alertsAsFailure })
    }

    @Test func eachCauseHasItsAlertText() {
        #expect(RefreshFailure.challenge.alertCause == "blocked by the provider's bot check")
        #expect(RefreshFailure.unauthorized.alertCause == "credential expired")
        #expect(RefreshFailure.httpStatus(503).alertCause == "server error 503")
        #expect(RefreshFailure.rateLimited(until: nil).alertCause == "rate limited")
        #expect(RefreshFailure.decoding.alertCause == "unexpected response")
        #expect(RefreshFailure.keychain.alertCause == "couldn't read Keychain")
        #expect(RefreshFailure.needsOrganization.alertCause == "choose an organization in Settings")
        #expect(RefreshFailure.unexpected.alertCause == "unexpected error")
        #expect(RefreshFailure.transport.alertCause == "couldn't reach the server")
        #expect(RefreshFailure.offline.alertCause == "network unavailable")
    }

    @Test func aFailureAlertNamesTheHalfAndTheCause() {
        let plan = AlertPolicy.failureAlert(displayName: "Anthropic", half: .subscription, cause: .unauthorized, provider: .anthropic)
        let spend = AlertPolicy.failureAlert(displayName: "OpenAI", half: .api, cause: .httpStatus(500), provider: .openai)

        #expect(plan == UsageAlert(key: "anthropic.subscription.failure", title: "Anthropic plan usage couldn't refresh", body: "Credential expired."))
        #expect(spend == UsageAlert(key: "openai.api.failure", title: "OpenAI API spend couldn't refresh", body: "Server error 500."))
    }
}

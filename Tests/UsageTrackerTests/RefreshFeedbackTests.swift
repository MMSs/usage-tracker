import Foundation
import Testing
@testable import UsageTracker

@Suite struct RefreshFeedbackTests {
    let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func aFreshButtonIsIdle() {
        let feedback = RefreshFeedback()

        #expect(feedback.phase == .idle)
        #expect(feedback.displayed(at: start) == .idle)
    }

    @Test func aClickWhileRefreshingIsIgnored() {
        var feedback = RefreshFeedback()

        let first = feedback.begin()
        let second = feedback.begin()
        #expect(first)
        #expect(!second)
        #expect(feedback.phase == .refreshing)
        #expect(feedback.displayed(at: start.addingTimeInterval(60)) == .refreshing)
    }

    @Test func successShowsForASecondAndAHalf() {
        var feedback = RefreshFeedback()
        _ = feedback.begin()
        feedback.finish(succeeded: true, now: start)

        #expect(feedback.displayed(at: start) == .succeeded)
        #expect(feedback.displayed(at: start.addingTimeInterval(1.4)) == .succeeded)
        #expect(feedback.displayed(at: start.addingTimeInterval(1.5)) == .idle)
        #expect(feedback.shownUntil == start.addingTimeInterval(RefreshFeedback.resultDuration))
    }

    @Test func failureShowsTheFailedPhase() {
        var feedback = RefreshFeedback()
        _ = feedback.begin()
        feedback.finish(succeeded: false, now: start)

        #expect(feedback.phase == .failed)
        #expect(feedback.displayed(at: start.addingTimeInterval(1.4)) == .failed)
        #expect(feedback.displayed(at: start.addingTimeInterval(1.5)) == .idle)
    }

    @Test func aNewClickAfterTheResultStartsAgain() {
        var feedback = RefreshFeedback()
        _ = feedback.begin()
        feedback.finish(succeeded: true, now: start)

        let restarted = feedback.begin()
        #expect(restarted)
        #expect(feedback.phase == .refreshing)
        #expect(feedback.shownUntil == nil)
        #expect(feedback.displayed(at: start.addingTimeInterval(0.1)) == .refreshing)
    }

    @Test func aFetchNobodyClickedForShowsTheSpinnerThenIdle() {
        let feedback = RefreshFeedback()

        #expect(RefreshFeedback.shown(feedback.displayed(at: start), fetching: true) == .refreshing)
        #expect(RefreshFeedback.shown(feedback.displayed(at: start), fetching: false) == .idle)
    }

    @Test func aFetchKeepsTheSpinnerOverAShownResult() {
        var feedback = RefreshFeedback()
        _ = feedback.begin()
        feedback.finish(succeeded: true, now: start)

        #expect(RefreshFeedback.shown(feedback.displayed(at: start), fetching: true) == .refreshing)
        #expect(RefreshFeedback.shown(feedback.displayed(at: start), fetching: false) == .succeeded)
    }
}

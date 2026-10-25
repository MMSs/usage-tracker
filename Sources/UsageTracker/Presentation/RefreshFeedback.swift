import Foundation

/// What the popover's Refresh button shows: idle, a spinner while fetching,
/// then a check or a cross for `resultDuration` before it goes idle again.
struct RefreshFeedback: Equatable {
    enum Phase: Equatable {
        case idle, refreshing, succeeded, failed
    }

    static let resultDuration: TimeInterval = 1.5

    private(set) var phase = Phase.idle
    private(set) var shownUntil: Date?

    /// Starts a refresh; false (and nothing changes) while one is running.
    mutating func begin() -> Bool {
        guard phase != .refreshing else {
            return false
        }

        phase = .refreshing
        shownUntil = nil
        return true
    }

    mutating func finish(succeeded: Bool, now: Date) {
        phase = succeeded ? .succeeded : .failed
        shownUntil = now.addingTimeInterval(Self.resultDuration)
    }

    /// The phase to draw at `now`: a result lapses to idle once it has been shown long enough.
    func displayed(at now: Date) -> Phase {
        guard let shownUntil else {
            return phase
        }

        return now >= shownUntil ? .idle : phase
    }

    /// The phase to show: the spinner whenever a fetch is running, even one
    /// nobody clicked for; a result only ever follows a click.
    static func shown(_ displayed: Phase, fetching: Bool) -> Phase {
        fetching ? .refreshing : displayed
    }
}

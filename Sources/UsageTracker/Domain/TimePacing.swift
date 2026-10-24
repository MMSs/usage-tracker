import Foundation

/// Where usage of a timed window (a 5-hour session, a 7-day week) should be
/// if spent evenly across the window.
enum TimePacing {
    /// The share of the window already elapsed, as a percentage clamped to 0…100.
    static func idealPercent(windowLength: TimeInterval, resetsAt: Date, now: Date) -> Double {
        let remaining = resetsAt.timeIntervalSince(now)
        let percent = 100 * (windowLength - remaining) / windowLength
        return min(max(percent, 0), 100)
    }

    /// The elapsed share as a fraction of 0…1; nil without a positive length or an open window.
    static func idealFraction(for window: LimitWindow, now: Date) -> Double? {
        guard let windowLength = window.windowLength, windowLength > 0, let resetsAt = window.resetsAt else {
            return nil
        }

        return idealPercent(windowLength: windowLength, resetsAt: resetsAt, now: now) / 100
    }
}

import Foundation

/// Runs the popover's Refresh click. The fetch gets a task of its own, so
/// closing the popover never cancels it; only the timer that idles the
/// result afterwards belongs to the popover and stops with it.
@MainActor
final class RefreshButtonModel: ObservableObject {
    typealias Sleep = @MainActor (Duration) async -> Void

    @Published private(set) var feedback = RefreshFeedback()

    private let sleep: Sleep
    private let now: () -> Date
    private var lapseTask: Task<Void, Never>?

    init(
        sleep: @escaping Sleep = { duration in
            try? await Task.sleep(for: duration)
        },
        now: @escaping () -> Date = Date.init
    ) {
        self.sleep = sleep
        self.now = now
    }

    /// Starts `refresh`, then shows its result for a moment; false (and
    /// nothing runs) while a clicked refresh, or any fetch (`fetching`), is
    /// still running.
    @discardableResult
    func click(fetching: Bool, _ refresh: @escaping @MainActor () async -> Bool) -> Bool {
        guard !fetching, feedback.begin() else {
            return false
        }

        lapseTask?.cancel()
        Task {
            let succeeded = await refresh()
            finish(succeeded: succeeded)
        }
        return true
    }

    /// The popover closed: the result's timer stops, a running fetch carries on.
    func panelClosed() {
        lapseTask?.cancel()
        lapseTask = nil
    }

    private func finish(succeeded: Bool) {
        feedback.finish(succeeded: succeeded, now: now())
        lapseTask?.cancel()
        lapseTask = Task { [sleep] in
            await sleep(.seconds(RefreshFeedback.resultDuration))
            guard !Task.isCancelled else {
                return
            }

            // Mutates the state the popover reads, so the result lapses to idle on screen.
            self.feedback.lapse(at: self.now())
        }
    }
}

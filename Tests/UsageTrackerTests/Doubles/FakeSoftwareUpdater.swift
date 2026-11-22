import Combine
@testable import UsageTracker

/// An updater the tests drive by hand; never touches Sparkle or the network.
@MainActor
final class FakeSoftwareUpdater: SoftwareUpdating {
    var automaticallyChecksForUpdates: Bool
    let canCheckSubject: CurrentValueSubject<Bool, Never>
    let pendingSubject = CurrentValueSubject<Bool, Never>(false)
    private(set) var checkCallCount = 0

    init(automatic: Bool = true, canCheck: Bool = true) {
        automaticallyChecksForUpdates = automatic
        canCheckSubject = CurrentValueSubject(canCheck)
    }

    var canCheckForUpdates: Bool {
        canCheckSubject.value
    }

    var canCheckForUpdatesPublisher: AnyPublisher<Bool, Never> {
        canCheckSubject.eraseToAnyPublisher()
    }

    var isUpdatePending: Bool {
        pendingSubject.value
    }

    var isUpdatePendingPublisher: AnyPublisher<Bool, Never> {
        pendingSubject.removeDuplicates().eraseToAnyPublisher()
    }

    func checkForUpdates() {
        checkCallCount += 1
    }
}

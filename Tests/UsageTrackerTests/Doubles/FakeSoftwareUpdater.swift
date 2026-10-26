import Combine
@testable import UsageTracker

/// An updater the tests drive by hand; never touches Sparkle or the network.
@MainActor
final class FakeSoftwareUpdater: SoftwareUpdating {
    var automaticallyChecksForUpdates: Bool
    let canCheckSubject: CurrentValueSubject<Bool, Never>
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

    func checkForUpdates() {
        checkCallCount += 1
    }
}

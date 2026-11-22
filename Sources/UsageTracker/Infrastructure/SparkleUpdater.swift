import AppKit
import Combine
import Sparkle

/// The real updater: Sparkle's standard controller and update windows, fed by
/// the appcast and public key a release build carries in its Info.plist.
@MainActor
final class SparkleUpdater: SoftwareUpdating {
    private let userDriverDelegate = UserDriverDelegate()
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: userDriverDelegate
        )
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    var canCheckForUpdatesPublisher: AnyPublisher<Bool, Never> {
        controller.updater
            .publisher(for: \.canCheckForUpdates, options: [.new])
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    var isUpdatePending: Bool {
        userDriverDelegate.pending.value
    }

    var isUpdatePendingPublisher: AnyPublisher<Bool, Never> {
        userDriverDelegate.pending.removeDuplicates().eraseToAnyPublisher()
    }

    /// Also how a pending update is shown: Sparkle brings up the update it found.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

/// Gentle reminders for a background app: a scheduled update found while the
/// user is busy elsewhere doesn't open a window; the menu bar shows a dot
/// instead until the user opens it or the update session ends. When Sparkle
/// does show a window, the app comes forward first, since it has no Dock
/// icon and the window would otherwise open behind the front app.
@MainActor
private final class UserDriverDelegate: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    let pending = CurrentValueSubject<Bool, Never>(false)

    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard handleShowingUpdate else {
            pending.send(true)
            return
        }
        NSApp.activate()
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        pending.send(false)
    }

    func standardUserDriverWillFinishUpdateSession() {
        pending.send(false)
    }
}

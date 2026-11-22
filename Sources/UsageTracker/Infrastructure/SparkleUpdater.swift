import AppKit
import Combine
import Sparkle

/// The real updater: Sparkle's standard controller and update windows, fed by
/// the appcast and public key a release build carries in its Info.plist.
@MainActor
final class SparkleUpdater: SoftwareUpdating {
    private let updaterDelegate = UpdaterDelegate()
    private let userDriverDelegate = UserDriverDelegate()
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: updaterDelegate,
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
        updaterDelegate.pending.value
    }

    var isUpdatePendingPublisher: AnyPublisher<Bool, Never> {
        updaterDelegate.pending.removeDuplicates().eraseToAnyPublisher()
    }

    /// Also how a pending update is shown: Sparkle brings up the update it found.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

/// Tracks whether an update is waiting, in the foreground or background: on
/// from the moment a check finds one until the user installs or skips it, or
/// a later check finds none. Closing Sparkle's window ("Later") keeps it on.
@MainActor
private final class UpdaterDelegate: NSObject, @preconcurrency SPUUpdaterDelegate {
    let pending = CurrentValueSubject<Bool, Never>(false)

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        pending.send(true)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        pending.send(false)
    }

    func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        switch choice {
        case .install, .skip:
            pending.send(false)
        case .dismiss:
            break
        @unknown default:
            break
        }
    }
}

/// The app has no Dock icon, so a scheduled update's window would otherwise
/// open behind whatever app is in front. Sparkle's guidance for background
/// apps is to support gentle reminders and bring the app forward when the
/// standard user driver is about to show an update.
@MainActor
private final class UserDriverDelegate: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard handleShowingUpdate else {
            return
        }
        NSApp.activate()
    }
}

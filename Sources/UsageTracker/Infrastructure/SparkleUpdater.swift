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

    func checkForUpdates() {
        controller.checkForUpdates(nil)
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

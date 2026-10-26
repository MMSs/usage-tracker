import Combine

/// The Updates section: the automatic-check switch, whether a check can start
/// now, and the version line. Without an updater (a build made from source)
/// the section only explains why and shows the version.
@MainActor
final class UpdatesModel: ObservableObject {
    @Published private(set) var isAutomatic: Bool
    @Published private(set) var canCheck: Bool

    private let updater: SoftwareUpdating?
    private let build: BuildInfo
    private var canCheckObserver: AnyCancellable?

    init(updater: SoftwareUpdating?, build: BuildInfo) {
        self.updater = updater
        self.build = build
        isAutomatic = updater?.automaticallyChecksForUpdates ?? false
        // The publisher emits on change only, so the first value is read directly.
        canCheck = updater?.canCheckForUpdates ?? false
        canCheckObserver = updater?.canCheckForUpdatesPublisher
            .sink { [weak self] in self?.canCheck = $0 }
    }

    var isAvailable: Bool {
        updater != nil
    }

    var message: String? {
        isAvailable ? nil : "Updates are off in builds made from source."
    }

    var versionText: String {
        build.versionText
    }

    func setAutomatic(_ isOn: Bool) {
        guard let updater else {
            return
        }

        updater.automaticallyChecksForUpdates = isOn
        isAutomatic = updater.automaticallyChecksForUpdates
    }

    func checkNow() {
        guard canCheck, let updater else {
            return
        }

        updater.checkForUpdates()
    }
}

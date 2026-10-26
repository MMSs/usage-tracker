import Combine

/// Checks for and installs new releases of the app.
@MainActor
protocol SoftwareUpdating: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var canCheckForUpdates: Bool { get }
    /// Emits the new value whenever `canCheckForUpdates` changes.
    var canCheckForUpdatesPublisher: AnyPublisher<Bool, Never> { get }
    func checkForUpdates()
}

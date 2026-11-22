import Combine

/// Checks for and installs new releases of the app.
@MainActor
protocol SoftwareUpdating: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var canCheckForUpdates: Bool { get }
    /// Emits the new value whenever `canCheckForUpdates` changes.
    var canCheckForUpdatesPublisher: AnyPublisher<Bool, Never> { get }
    /// True while a background check found an update the user hasn't seen yet.
    var isUpdatePending: Bool { get }
    /// Emits the new value whenever `isUpdatePending` changes.
    var isUpdatePendingPublisher: AnyPublisher<Bool, Never> { get }
    func checkForUpdates()
}

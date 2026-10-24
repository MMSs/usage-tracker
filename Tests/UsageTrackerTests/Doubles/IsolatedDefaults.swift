import Foundation

/// A throwaway `UserDefaults` for one test.
///
/// The suite name is a path inside a temporary directory, so its plist lives
/// there and not in `~/Library/Preferences`, where a named suite leaves a file
/// behind even after `removePersistentDomain`. `remove()` clears the domain and
/// deletes the directory.
struct IsolatedDefaults {
    let defaults: UserDefaults
    /// The domain name, for APIs that take one (`persistentDomain(forName:)`).
    let suiteName: String
    private let directory: URL

    init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UsageTrackerTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = directory.appendingPathComponent("defaults").path
        defaults = UserDefaults(suiteName: suiteName)!
    }

    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Runs `body` against a fresh `UserDefaults` and removes it afterwards.
func withIsolatedDefaults<T>(_ body: (UserDefaults) throws -> T) rethrows -> T {
    let isolated = IsolatedDefaults()
    defer { isolated.remove() }

    return try body(isolated.defaults)
}

import Foundation
import os

/// Clears `com.apple.quarantine` from the running bundle once a launch has
/// passed Gatekeeper.
///
/// Homebrew installs a quarantined bundle, and the first launch is meant to
/// come from the user so the first-open prompt can approve it. When the app
/// is a login item, launchd can start a freshly installed copy instead, and
/// the quarantine then survives unapproved. Its next evaluation happens at the
/// following login, where Gatekeeper may be unable to reach the notarization
/// service and rejects the app with the "could not verify it is free of
/// malware" dialog. A running app has already passed Gatekeeper, so the flag
/// buys nothing further and clearing it keeps later launches out of that
/// evaluation. Sparkle does the same for the updates it installs.
struct QuarantineRemover {
    static let attributeName = "com.apple.quarantine"

    let bundleURL: URL

    /// Removes the attribute from the bundle and everything inside it.
    /// Returns how many items carried it. An item that cannot be changed,
    /// such as one in a root-owned bundle, is left alone.
    @discardableResult
    func run() -> Int {
        var cleared = 0
        for item in items() where remove(from: item) {
            cleared += 1
        }
        if cleared > 0 {
            Log.quarantine.notice("cleared quarantine from \(cleared, privacy: .public) items")
        }
        return cleared
    }

    private func items() -> [URL] {
        guard FileManager.default.fileExists(atPath: bundleURL.path) else {
            return []
        }
        var items = [bundleURL]
        if let enumerator = FileManager.default.enumerator(
            at: bundleURL,
            includingPropertiesForKeys: nil,
            options: [.producesRelativePathURLs]
        ) {
            for case let item as URL in enumerator {
                items.append(item)
            }
        }
        return items
    }

    /// True when the attribute was there and is now gone.
    private func remove(from item: URL) -> Bool {
        removexattr(item.path, Self.attributeName, XATTR_NOFOLLOW) == 0
    }
}

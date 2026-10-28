import Foundation
import Security

/// What this copy of the app was signed to use. CloudKit traps when the app
/// lacks the iCloud container entitlement, so it is checked before CloudKit
/// is touched; builds made from source and CI builds have neither.
enum SyncEntitlements {
    static let containerIdentifier = "iCloud.com.mohabsam.usage-tracker"

    static var hasCloudKit: Bool {
        (value("com.apple.developer.icloud-container-identifiers") as? [String])?.contains(containerIdentifier) == true
    }

    /// Synced Keychain items need a keychain access group.
    static var hasKeychainSharing: Bool {
        (value("keychain-access-groups") as? [String])?.isEmpty == false
    }

    private static func value(_ entitlement: String) -> Any? {
        guard let task = SecTaskCreateFromSelf(nil) else {
            return nil
        }

        return SecTaskCopyValueForEntitlement(task, entitlement as CFString, nil)
    }
}

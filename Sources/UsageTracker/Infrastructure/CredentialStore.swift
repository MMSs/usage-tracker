import Foundation
import Security

struct CredentialKey: Hashable, Sendable {
    let provider: Provider
    let fieldID: String

    var account: String { "\(provider.rawValue)-\(fieldID)" }
}

protocol CredentialStoring: AnyObject {
    func credential(for key: CredentialKey) throws -> String?
    /// Whether an item exists, without returning the secret.
    func hasCredential(for key: CredentialKey) throws -> Bool
    func set(_ value: String, for key: CredentialKey) throws
    func remove(_ key: CredentialKey) throws
}

private enum KeychainCredentialStoreError: Error {
    case unexpectedStatus(OSStatus)
    case invalidValue
}

final class KeychainCredentialStore: CredentialStoring {
    private static let service = "com.mohab.usage-tracker"

    func credential(for key: CredentialKey) throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
                throw KeychainCredentialStoreError.invalidValue
            }

            return value
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainCredentialStoreError.unexpectedStatus(status)
        }
    }

    func hasCredential(for key: CredentialKey) throws -> Bool {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = false
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        switch SecItemCopyMatching(query as CFDictionary, nil) {
        case errSecSuccess: return true
        case errSecItemNotFound: return false
        case let status: throw KeychainCredentialStoreError.unexpectedStatus(status)
        }
    }

    func set(_ value: String, for key: CredentialKey) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(
            baseQuery(for: key) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if status == errSecSuccess {
            return
        }

        guard status == errSecItemNotFound else {
            throw KeychainCredentialStoreError.unexpectedStatus(status)
        }

        var addQuery = baseQuery(for: key)
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

        guard addStatus == errSecSuccess else {
            throw KeychainCredentialStoreError.unexpectedStatus(addStatus)
        }
    }

    func remove(_ key: CredentialKey) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainCredentialStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(for key: CredentialKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: key.account,
        ]
    }
}

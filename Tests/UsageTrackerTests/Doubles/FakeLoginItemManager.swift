import Foundation
@testable import UsageTracker

/// A login item the tests drive by hand; never touches `SMAppService`.
final class FakeLoginItemManager: LoginItemManaging {
    struct Failure: Error, LocalizedError {
        var errorDescription: String? { "the fake failed" }
    }

    var status: LoginItemStatus
    var registerError: (any Error)?
    var unregisterError: (any Error)?
    /// What `register()` leaves the status at; `nil` means enabled.
    var statusAfterRegister: LoginItemStatus?
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    private(set) var openSettingsCallCount = 0

    init(status: LoginItemStatus = .notRegistered) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
        if let registerError {
            throw registerError
        }
        status = statusAfterRegister ?? .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError {
            throw unregisterError
        }
        status = .notRegistered
    }

    func openSystemSettings() {
        openSettingsCallCount += 1
    }
}

final class MemoryLoginItemPreferenceStore: LoginItemPreferenceStoring {
    private(set) var stored: Bool?

    init(_ stored: Bool? = nil) {
        self.stored = stored
    }

    func preference() -> Bool? {
        stored
    }

    func setPreference(_ isOn: Bool) {
        stored = isOn
    }
}

extension LoginItemModel {
    /// A model over a fake manager and an in-memory preference, for tests that only need one to exist.
    @MainActor static func stub() -> LoginItemModel {
        LoginItemModel(manager: FakeLoginItemManager(), store: MemoryLoginItemPreferenceStore())
    }
}

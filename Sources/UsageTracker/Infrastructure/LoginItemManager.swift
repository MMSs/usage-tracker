import ServiceManagement

/// What macOS says about the app's login item, independent of `SMAppService`
/// so tests can drive it.
enum LoginItemStatus: String, Equatable {
    case enabled
    case notRegistered
    /// Registered, but the user has not allowed it (or switched it off) in System Settings.
    case requiresApproval
    case notFound

    init(_ status: SMAppService.Status) {
        switch status {
        case .enabled: self = .enabled
        case .notRegistered: self = .notRegistered
        case .requiresApproval: self = .requiresApproval
        case .notFound: self = .notFound
        @unknown default: self = .notFound
        }
    }
}

protocol LoginItemManaging {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
    /// Opens System Settings at Login Items & Extensions.
    func openSystemSettings()
}

struct LoginItemManager: LoginItemManaging {
    var status: LoginItemStatus {
        LoginItemStatus(SMAppService.mainApp.status)
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

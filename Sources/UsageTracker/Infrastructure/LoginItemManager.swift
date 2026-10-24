import ServiceManagement

protocol LoginItemManaging {
    func registerAtLogin()
}

struct AppStartup {
    static func configure(loginItemManager: LoginItemManaging) {
        loginItemManager.registerAtLogin()
    }
}

final class LoginItemManager: LoginItemManaging {
    func registerAtLogin() {
        guard SMAppService.mainApp.status != .enabled else {
            return
        }

        try? SMAppService.mainApp.register()
    }
}

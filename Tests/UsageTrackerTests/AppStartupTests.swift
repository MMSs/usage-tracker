import Testing
@testable import UsageTracker

@Test func appStartupRequestsLoginRegistration() {
    let manager = RecordingLoginItemManager()

    AppStartup.configure(loginItemManager: manager)

    #expect(manager.registerCallCount == 1)
}

final class RecordingLoginItemManager: LoginItemManaging {
    var registerCallCount = 0

    func registerAtLogin() {
        registerCallCount += 1
    }
}

import Testing
@testable import UsageTracker

@Suite @MainActor struct UpdatesModelTests {
    private let release = BuildInfo(infoDictionary: ["CFBundleShortVersionString": "1.0.0"])

    @Test func reflectsTheUpdatersSettings() {
        let model = UpdatesModel(updater: FakeSoftwareUpdater(automatic: true, canCheck: true), build: release)

        #expect(model.isAutomatic)
        #expect(model.canCheck)
        #expect(model.isAvailable)
    }

    @Test func switchingOffAutomaticChecksSetsTheUpdater() {
        let updater = FakeSoftwareUpdater(automatic: true)
        let model = UpdatesModel(updater: updater, build: release)

        model.setAutomatic(false)

        #expect(updater.automaticallyChecksForUpdates == false)
        #expect(model.isAutomatic == false)
    }

    @Test func canCheckFollowsTheUpdater() {
        let updater = FakeSoftwareUpdater(canCheck: true)
        let model = UpdatesModel(updater: updater, build: release)

        updater.canCheckSubject.send(false)
        #expect(model.canCheck == false)
        model.checkNow()
        #expect(updater.checkCallCount == 0)

        updater.canCheckSubject.send(true)
        model.checkNow()
        #expect(updater.checkCallCount == 1)
    }

    @Test func showsTheVersion() {
        let model = UpdatesModel(updater: FakeSoftwareUpdater(), build: release)

        #expect(model.versionText == "Version 1.0.0")
        #expect(model.message == nil)
    }

    @Test func aSourceBuildHasNoUpdater() {
        let model = UpdatesModel(updater: nil, build: BuildInfo(infoDictionary: nil))

        #expect(model.isAvailable == false)
        #expect(model.message == "Updates are off in builds made from source.")
        #expect(model.versionText == "Version dev")
        model.checkNow()
        model.setAutomatic(true)
        #expect(model.isAutomatic == false)
    }
}

import Foundation
import ServiceManagement
import Testing
@testable import UsageTracker

@Suite struct LoginItemStatusTests {
    @Test func theSystemStatusesMapOneToOne() {
        #expect(LoginItemStatus(SMAppService.Status.enabled) == .enabled)
        #expect(LoginItemStatus(SMAppService.Status.notRegistered) == .notRegistered)
        #expect(LoginItemStatus(SMAppService.Status.requiresApproval) == .requiresApproval)
        #expect(LoginItemStatus(SMAppService.Status.notFound) == .notFound)
    }
}

@Suite @MainActor struct LoginItemModelTests {
    private func makeModel(
        status: LoginItemStatus = .notRegistered,
        stored: Bool? = nil,
        defaults: UserDefaults
    ) -> (model: LoginItemModel, manager: FakeLoginItemManager, store: UserDefaultsLoginItemPreferenceStore) {
        let manager = FakeLoginItemManager(status: status)
        let store = UserDefaultsLoginItemPreferenceStore(defaults: defaults)
        if let stored {
            store.setPreference(stored)
        }
        return (LoginItemModel(manager: manager, store: store), manager, store)
    }

    // MARK: Launch

    @Test func theFirstLaunchRegistersAndRemembersIt() {
        withIsolatedDefaults { defaults in
            let (model, manager, store) = makeModel(defaults: defaults)

            model.reconcileAtLaunch()

            #expect(manager.registerCallCount == 1)
            #expect(store.preference() == true)
            #expect(model.isOn)
            #expect(model.status == .enabled)
            #expect(model.failure == nil)
        }
    }

    @Test func theFirstLaunchAdoptsAnItemThatIsAlreadyEnabled() {
        withIsolatedDefaults { defaults in
            let (model, manager, store) = makeModel(status: .enabled, defaults: defaults)

            model.reconcileAtLaunch()

            #expect(manager.registerCallCount == 0)
            #expect(store.preference() == true)
        }
    }

    @Test func aFailedFirstRegistrationSurfacesAndRetriesNextLaunch() {
        withIsolatedDefaults { defaults in
            let (model, manager, store) = makeModel(defaults: defaults)
            manager.registerError = FakeLoginItemManager.Failure()

            model.reconcileAtLaunch()

            #expect(store.preference() == nil)
            #expect(!model.isOn)
            #expect(model.failure?.contains("the fake failed") == true)

            manager.registerError = nil
            model.reconcileAtLaunch()

            #expect(manager.registerCallCount == 2)
            #expect(store.preference() == true)
            #expect(model.failure == nil)
        }
    }

    @Test func anItemTheUserRemovedInSystemSettingsStaysOff() {
        withIsolatedDefaults { defaults in
            let (model, manager, store) = makeModel(status: .notRegistered, stored: true, defaults: defaults)

            model.reconcileAtLaunch()

            #expect(manager.registerCallCount == 0)
            #expect(store.preference() == false)
            #expect(!model.isOn)
        }
    }

    @Test func aLaunchAfterTurningItOffDoesNotRegister() {
        withIsolatedDefaults { defaults in
            let (model, manager, _) = makeModel(status: .notRegistered, stored: false, defaults: defaults)

            model.reconcileAtLaunch()

            #expect(manager.registerCallCount == 0)
            #expect(!model.isOn)
        }
    }

    @Test func anEnabledItemWithPreferenceOnIsLeftAlone() {
        withIsolatedDefaults { defaults in
            let (model, manager, store) = makeModel(status: .enabled, stored: true, defaults: defaults)

            model.reconcileAtLaunch()

            #expect(manager.registerCallCount == 0)
            #expect(manager.unregisterCallCount == 0)
            #expect(store.preference() == true)
            #expect(model.isOn)
        }
    }

    @Test func anItemNeedingApprovalKeepsThePreferenceAndShowsTheStatus() {
        withIsolatedDefaults { defaults in
            let (model, manager, store) = makeModel(status: .requiresApproval, stored: true, defaults: defaults)

            model.reconcileAtLaunch()

            #expect(manager.registerCallCount == 0)
            #expect(store.preference() == true)
            #expect(model.status == .requiresApproval)
        }
    }

    // MARK: Refresh

    @Test func refreshPicksUpAnItemRemovedWhileTheAppRuns() {
        withIsolatedDefaults { defaults in
            let (model, manager, store) = makeModel(status: .enabled, stored: true, defaults: defaults)
            model.reconcileAtLaunch()

            manager.status = .notRegistered
            model.refresh()

            #expect(model.status == .notRegistered)
            #expect(!model.isOn)
            #expect(store.preference() == false)
            #expect(manager.registerCallCount == 0)
        }
    }

    @Test func refreshPicksUpAnItemTheUserAddedInSystemSettings() {
        withIsolatedDefaults { defaults in
            let (model, manager, store) = makeModel(status: .notRegistered, stored: false, defaults: defaults)
            model.reconcileAtLaunch()

            manager.status = .enabled
            model.refresh()

            #expect(model.isOn)
            #expect(store.preference() == true)
        }
    }

    @Test func refreshClearsAFailureAndReadsTheLiveStatus() {
        withIsolatedDefaults { defaults in
            let (model, manager, _) = makeModel(status: .notRegistered, stored: false, defaults: defaults)
            manager.registerError = FakeLoginItemManager.Failure()
            model.setOn(true)
            #expect(model.failure != nil)

            manager.status = .requiresApproval
            model.refresh()

            #expect(model.failure == nil)
            #expect(model.status == .requiresApproval)
        }
    }

    // MARK: The switch

    @Test func turningTheSwitchOnRegistersAndRemembersIt() {
        withIsolatedDefaults { defaults in
            let (model, manager, store) = makeModel(status: .notRegistered, stored: false, defaults: defaults)

            model.setOn(true)

            #expect(manager.registerCallCount == 1)
            #expect(store.preference() == true)
            #expect(model.isOn)
            #expect(model.status == .enabled)
        }
    }

    @Test func turningTheSwitchOffUnregistersAndRemembersIt() {
        withIsolatedDefaults { defaults in
            let (model, manager, store) = makeModel(status: .enabled, stored: true, defaults: defaults)

            model.setOn(false)

            #expect(manager.unregisterCallCount == 1)
            #expect(store.preference() == false)
            #expect(!model.isOn)
            #expect(model.status == .notRegistered)
        }
    }

    @Test func aFailedRegistrationLeavesTheSwitchOffAndShowsTheMessage() {
        withIsolatedDefaults { defaults in
            let (model, manager, store) = makeModel(status: .notRegistered, stored: false, defaults: defaults)
            manager.registerError = FakeLoginItemManager.Failure()

            model.setOn(true)

            #expect(!model.isOn)
            #expect(store.preference() == false)
            #expect(model.failure?.contains("the fake failed") == true)
        }
    }

    @Test func aFailedUnregistrationLeavesTheSwitchOnAndShowsTheMessage() {
        withIsolatedDefaults { defaults in
            let (model, manager, store) = makeModel(status: .enabled, stored: true, defaults: defaults)
            manager.unregisterError = FakeLoginItemManager.Failure()

            model.setOn(false)

            #expect(model.isOn)
            #expect(store.preference() == true)
            #expect(model.failure?.contains("the fake failed") == true)
        }
    }

    @Test func aSuccessfulSwitchClearsAnEarlierFailure() {
        withIsolatedDefaults { defaults in
            let (model, manager, _) = makeModel(status: .notRegistered, stored: false, defaults: defaults)
            manager.registerError = FakeLoginItemManager.Failure()
            model.setOn(true)

            manager.registerError = nil
            model.setOn(true)

            #expect(model.failure == nil)
            #expect(model.isOn)
        }
    }

    // MARK: Presentation

    @Test func theStatusLineFollowsTheLiveStatus() {
        withIsolatedDefaults { defaults in
            let (model, manager, _) = makeModel(status: .enabled, stored: true, defaults: defaults)
            model.refresh()
            #expect(model.statusLine == "Opens when you log in")
            #expect(!model.needsApproval)

            manager.status = .requiresApproval
            model.refresh()
            #expect(model.statusLine == "Needs approval in System Settings")
            #expect(model.needsApproval)

            manager.status = .notFound
            model.refresh()
            #expect(model.statusLine == "macOS can't find the app. Open the copy in Applications.")

            manager.status = .notRegistered
            model.refresh()
            #expect(model.statusLine == nil)
        }
    }

    @Test func aFailureReplacesTheStatusLine() {
        withIsolatedDefaults { defaults in
            let (model, manager, _) = makeModel(status: .notRegistered, stored: false, defaults: defaults)
            manager.registerError = FakeLoginItemManager.Failure()

            model.setOn(true)

            #expect(model.statusLine == "Couldn't turn on Open at login: the fake failed")
        }
    }

    @Test func openingSystemSettingsCallsThrough() {
        withIsolatedDefaults { defaults in
            let (model, manager, _) = makeModel(defaults: defaults)

            model.openSystemSettings()

            #expect(manager.openSettingsCallCount == 1)
        }
    }
}

import AppKit
import Testing
@testable import UsageTracker

@Suite @MainActor struct SettingsWindowControllerTests {
    @MainActor
    final class RecordingDock: DockPresenting {
        var visibility: [Bool] = []
        var activations = 0
        func setVisible(_ visible: Bool) { visibility.append(visible) }
        func activate() { activations += 1 }
    }

    private func makeModel() -> AppModel {
        let credentials = MemoryCredentialStore()
        let providers = ProviderRegistry.all.map { descriptor in
            ProviderViewModel(
                descriptor: descriptor,
                subscriptionFetcher: descriptor.id == .cursor ? StubReportFetcher(result: .success(makeReport(1))) : nil,
                apiFetcher: nil,
                credentialStore: credentials, cache: MemoryReportCache()
            )
        }

        return AppModel(
            providers: providers,
            credentialStore: credentials,
            intervalStore: MemoryIntervalStore(.default),
            appearanceStore: MemoryMenuBarAppearanceStore(),
            budgetStore: MemoryAPIBudgetStore(),
            sleepObserver: ControllableSleepObserver(),
            networkObserver: ControllableNetworkObserver()
        )
    }

    @Test func presentingShowsTheDockAndClosingHidesIt() throws {
        let dock = RecordingDock()
        let controller = SettingsWindowController(model: makeModel(), dock: dock, frameAutosaveName: nil)

        controller.present(SettingsRequest(provider: .cursor, opensHelp: true))

        let window = try #require(controller.window)
        #expect(window.isVisible)
        #expect(dock.visibility == [true])
        #expect(dock.activations == 1)
        #expect(window.frame.width >= 640 && window.frame.height >= 440, "frame \(window.frame)")
        #expect(controller.selection.page == .provider(.cursor))
        #expect(controller.selection.helpProvider == .cursor)

        window.close()

        #expect(dock.visibility == [true, false])
        #expect(controller.window == nil)
    }

    @Test func presentingAgainReusesTheOpenWindow() throws {
        let dock = RecordingDock()
        let controller = SettingsWindowController(model: makeModel(), dock: dock, frameAutosaveName: nil)

        controller.present(.general)
        let first = try #require(controller.window)
        controller.present(SettingsRequest(provider: .cursor))

        #expect(controller.window === first)
        #expect(controller.selection.page == .provider(.cursor))
        first.close()
    }

    @Test func reopenKeepsThePageWhenOpenAndStartsOnGeneralOtherwise() throws {
        let dock = RecordingDock()
        let controller = SettingsWindowController(model: makeModel(), dock: dock, frameAutosaveName: nil)

        controller.showKeepingSelection()
        #expect(controller.selection.page == .general)

        controller.present(SettingsRequest(provider: .cursor, opensHelp: true))
        controller.showKeepingSelection()

        #expect(controller.selection.page == .provider(.cursor))
        #expect(controller.selection.helpProvider == .cursor)
        try #require(controller.window).close()
    }
}

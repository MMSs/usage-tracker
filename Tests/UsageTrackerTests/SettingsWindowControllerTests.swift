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

    private func makeModel(withHalves wired: Set<Provider> = [.cursor]) -> AppModel {
        let credentials = MemoryCredentialStore()
        let providers = ProviderRegistry.all.map { descriptor in
            ProviderViewModel(
                descriptor: descriptor,
                subscriptionFetcher: wired.contains(descriptor.id) ? StubReportFetcher(result: .success(makeReport(1))) : nil,
                apiFetcher: nil,
                credentialStore: credentials, cache: MemoryReportCache()
            )
        }

        return AppModel(
            providers: providers,
            credentialStore: credentials,
            providerSettingsStore: MemoryProviderSettingsStore(),
            appearanceStore: MemoryMenuBarAppearanceStore(),
            budgetStore: MemoryAPIBudgetStore(),
            loginItem: .stub(),
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
        #expect(abs(window.contentRect(forFrameRect: window.frame).width - SettingsLayout.pageWidth) < 1, "frame \(window.frame)")
        #expect(controller.pages == [.general, .provider(.cursor)])
        #expect(controller.selection.page == .provider(.cursor))
        #expect(controller.selection.helpProvider == .cursor)

        window.close()

        #expect(dock.visibility == [true, false])
        #expect(controller.window == nil)
    }

    @Test func toolbarTabsFollowTheMenuBarOrder() {
        let controller = SettingsWindowController(
            model: makeModel(withHalves: [.cursor, .anthropic]), dock: RecordingDock(), frameAutosaveName: nil
        )

        #expect(controller.pages == [.general, .provider(.anthropic), .provider(.cursor)])
    }

    @Test func toolbarTabsListOpenAIFirst() {
        let controller = SettingsWindowController(
            model: makeModel(withHalves: [.cursor, .anthropic, .openai]), dock: RecordingDock(), frameAutosaveName: nil
        )

        #expect(controller.pages == [.general, .provider(.openai), .provider(.anthropic), .provider(.cursor)])
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

    @Test func closingTheWindowForgetsTheTabs() throws {
        let controller = SettingsWindowController(model: makeModel(), dock: RecordingDock(), frameAutosaveName: nil)

        controller.present(SettingsRequest(provider: .cursor))
        controller.selection.selectTab(.menuBar, for: .cursor)
        try #require(controller.window).close()

        #expect(controller.selection.tabs.isEmpty)
    }

    @Test func switchingTabsFitsTheWindowToTheTab() throws {
        let controller = SettingsWindowController(model: makeModel(), dock: RecordingDock(), frameAutosaveName: nil)
        controller.present(SettingsRequest(provider: .cursor))
        let window = try #require(controller.window)
        func contentHeight() -> CGFloat {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            return window.contentRect(forFrameRect: window.frame).height
        }

        let subscriptionHeight = contentHeight()
        controller.selection.selectTab(.menuBar, for: .cursor)
        let menuBarHeight = contentHeight()
        controller.selection.selectTab(.subscription, for: .cursor)

        #expect(menuBarHeight != subscriptionHeight)
        #expect(contentHeight() == subscriptionHeight)
        window.close()
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

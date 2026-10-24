import SwiftUI

@main
struct UsageTrackerApp: App {
    nonisolated static let applicationName = "Usage Tracker"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        UserDefaults.standard.register(defaults: ["AppleKeyboardUIMode": 2])
    }

    var body: some Scene {
        let model = delegate.model
        // Scenes cannot be generated with ForEach, so one per registry slot.
        ProviderMenuBarScene(provider: model.providers[0], model: model)
        ProviderMenuBarScene(provider: model.providers[1], model: model)
        ProviderMenuBarScene(provider: model.providers[2], model: model)
    }
}

struct ProviderMenuBarScene: Scene {
    @ObservedObject var provider: ProviderViewModel
    @ObservedObject var model: AppModel

    @AppStorage(UserDefaultsMenuBarAppearanceStore.showTextKey) private var showText = MenuBarAppearance.default.showText
    @AppStorage(UserDefaultsMenuBarAppearanceStore.countdownKey) private var countdown = MenuBarAppearance.default.countdown
    @AppStorage(UserDefaultsMenuBarAppearanceStore.showGraphKey) private var showGraph = MenuBarAppearance.default.showGraph
    @AppStorage(UserDefaultsMenuBarAppearanceStore.graphStyleKey) private var graphStyle = MenuBarAppearance.default.graphStyle.rawValue
    @AppStorage(UserDefaultsMenuBarAppearanceStore.coloredKey) private var colored = MenuBarAppearance.default.colored

    private var appearance: MenuBarAppearance {
        MenuBarAppearance(
            showText: showText,
            countdown: countdown,
            showGraph: showGraph,
            graphStyle: MenuBarGraphStyle(rawValue: graphStyle) ?? MenuBarAppearance.default.graphStyle,
            colored: colored
        )
    }

    private var item: MenuBarItem {
        return MenuBarItemBuilder.make(
            descriptor: provider.descriptor,
            subscription: provider.subscription.map(HalfSnapshot.init),
            api: provider.api.map(HalfSnapshot.init),
            apiBudget: model.budgetStore.budget(for: provider.id),
            now: Date(),
            forceSetUp: !provider.isConfigured
        ) ?? MenuBarItem(provider: provider.id, subscription: .status(.loading), api: nil)
    }

    var body: some Scene {
        MenuBarExtra(
            isInserted: Binding(
                get: { model.insertedProviders.contains(provider.id) },
                set: { _ in }
            )
        ) {
            ProviderPopoverView(provider: provider, appModel: model)
        } label: {
            MenuBarLabel(item: item, appearance: appearance, displayName: provider.descriptor.displayName)
                .task {
                    // Idempotent, so any inserted scene may start the refresh cycle.
                    model.start()
                }
        }
        .menuBarExtraStyle(.window)
    }
}

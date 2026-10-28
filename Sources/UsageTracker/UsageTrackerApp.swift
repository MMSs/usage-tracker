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

    private var appearance: MenuBarAppearance {
        model.appearance(for: provider.id)
    }

    private var item: MenuBarItem {
        let now = Date()
        return MenuBarItemBuilder.make(
            descriptor: provider.descriptor,
            subscription: provider.snapshot(.subscription),
            api: provider.snapshot(.api),
            apiBudget: model.budget(for: provider.id),
            now: now
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
            label
                .task {
                    // Idempotent, so any inserted scene may start the refresh cycle.
                    model.start()
                }
        }
        .menuBarExtraStyle(.window)
    }

    /// While nothing is configured, this scene hosts the app's set-up item.
    @ViewBuilder
    private var label: some View {
        if model.showsSetUpItem {
            SetUpMenuBarLabel(appName: UsageTrackerApp.applicationName)
        } else {
            MenuBarLabel(item: item, appearance: appearance, halves: model.menuBarHalves(for: provider.id), displayName: provider.descriptor.displayName)
        }
    }
}

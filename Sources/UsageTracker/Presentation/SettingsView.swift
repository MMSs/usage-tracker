import SwiftUI

/// Sidebar selection shared between the window controller, which applies
/// requests, and the view, which the user navigates.
@MainActor
final class SettingsSelection: ObservableObject {
    @Published var page: SettingsPage = .general
    /// The provider whose first credential help starts open, until the user leaves its page.
    @Published var helpProvider: Provider?

    func apply(_ request: SettingsRequest, listed: [Provider]) {
        page = SettingsPage.resolve(request, listed: listed)
        helpProvider = request.opensHelp ? request.provider : nil
    }
}

struct SettingsView: View {
    @ObservedObject var appModel: AppModel
    @ObservedObject var selection: SettingsSelection

    /// The field whose help starts open: the requested provider's first field.
    static func helpFieldID(for descriptor: ProviderDescriptor, helpProvider: Provider?) -> String? {
        guard descriptor.id == helpProvider else {
            return nil
        }

        return (descriptor.subscriptionFields + descriptor.apiFields).first?.id
    }

    /// Providers with nothing to fetch yet are left out, so no credential is stored unused.
    private var listedProviders: [ProviderViewModel] {
        appModel.providers.filter(\.hasAnyHalf)
    }

    private var pageBinding: Binding<SettingsPage?> {
        Binding(
            get: { selection.page },
            set: { newValue in
                if let newValue {
                    selection.page = newValue
                }
            }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: pageBinding) {
                Label("General", systemImage: "gearshape")
                    .tag(SettingsPage.general)

                Section("Providers") {
                    ForEach(listedProviders) { provider in
                        Label {
                            Text(provider.descriptor.displayName)
                        } icon: {
                            ProviderGlyph(provider: provider.id)
                                .fill(.primary)
                                .frame(width: 14, height: 14)
                        }
                        .tag(SettingsPage.provider(provider.id))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 220)
        } detail: {
            switch selection.page {
            case .general:
                GeneralSettingsView(appModel: appModel)
                    .navigationTitle("General")
            case .provider(let id):
                let provider = appModel.provider(id)
                ProviderSettingsView(
                    provider: provider,
                    appModel: appModel,
                    helpFieldID: Self.helpFieldID(for: provider.descriptor, helpProvider: selection.helpProvider)
                )
                .navigationTitle(provider.descriptor.displayName)
                // Providers share field ids (admin-key, api-budget); a fresh identity per page keeps their state apart.
                .id(id)
            }
        }
        .frame(minWidth: 580, minHeight: 400)
        .onChange(of: selection.page) { _, page in
            if case .provider(let id) = page, id == selection.helpProvider {
                return
            }
            selection.helpProvider = nil
        }
    }
}

struct ProviderSettingsView: View {
    @ObservedObject var provider: ProviderViewModel
    let appModel: AppModel
    let helpFieldID: String?

    var body: some View {
        Form {
            Section {
                ForEach(provider.descriptor.subscriptionFields + provider.descriptor.apiFields) { field in
                    CredentialFieldView(
                        field: field,
                        key: CredentialKey(provider: provider.id, fieldID: field.id),
                        store: appModel.credentialStore,
                        budgetStore: appModel.budgetStore,
                        opensHelp: field.id == helpFieldID,
                        onChange: { await appModel.provider(provider.id).credentialsChanged(half: field.half) }
                    )
                }
            }
        }
        .formStyle(.grouped)
        // The title bar's scroll-edge effect blurs a pinned header within about 100pt of the top.
        .contentMargins(.top, 40, for: .scrollContent)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var appModel: AppModel

    @State private var appearance: MenuBarAppearance
    @State private var interval: RefreshInterval

    init(appModel: AppModel) {
        self.appModel = appModel
        _appearance = State(initialValue: appModel.appearanceStore.appearance())
        _interval = State(initialValue: appModel.intervalStore.interval())
    }

    var body: some View {
        Form {
            Section("Menu bar") {
                preview

                Toggle("Show text", isOn: binding(\.showText) { $0.showingText($1) })
                    .disabled(appearance.showText && !appearance.showGraph)
                Toggle("Countdown", isOn: binding(\.countdown) { var copy = $0; copy.countdown = $1; return copy })
                Toggle("Show graph", isOn: binding(\.showGraph) { $0.showingGraph($1) })
                    .disabled(appearance.showGraph && !appearance.showText)

                Picker("Graph style", selection: binding(\.graphStyle) { var copy = $0; copy.graphStyle = $1; return copy }) {
                    ForEach(MenuBarGraphStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Colored", isOn: binding(\.colored) { var copy = $0; copy.colored = $1; return copy })
            }

            Section("Refresh") {
                Picker("Every", selection: Binding(
                    get: { interval },
                    set: { newValue in
                        interval = newValue
                        appModel.setInterval(newValue)
                    }
                )) {
                    ForEach(RefreshInterval.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        // The title bar's scroll-edge effect blurs a pinned header within about 100pt of the top.
        .contentMargins(.top, 40, for: .scrollContent)
        .onAppear {
            appearance = appModel.appearanceStore.appearance()
            interval = appModel.intervalStore.interval()
        }
    }

    /// The configured provider shown in the preview, else the first listed one.
    private var previewProvider: ProviderViewModel? {
        appModel.providers.first(where: \.isConfigured) ?? appModel.providers.first(where: \.hasAnyHalf)
    }

    @ViewBuilder
    private var preview: some View {
        let provider = previewProvider
        let item = provider.flatMap { provider in
            MenuBarItemBuilder.make(
                descriptor: provider.descriptor,
                subscription: provider.subscription.map(HalfSnapshot.init),
                api: provider.api.map(HalfSnapshot.init),
                apiBudget: appModel.budgetStore.budget(for: provider.id),
                now: Date()
            )
        }

        LabeledContent("Preview") {
            if let provider, let item {
                MenuBarLabel(item: item, appearance: appearance, displayName: provider.descriptor.displayName)
            } else {
                Text("No data yet")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Reads one appearance property and writes changes through the store; `apply` may refuse a change.
    private func binding<Value>(
        _ keyPath: KeyPath<MenuBarAppearance, Value>,
        apply: @escaping (MenuBarAppearance, Value) -> MenuBarAppearance
    ) -> Binding<Value> {
        Binding(
            get: { appearance[keyPath: keyPath] },
            set: { newValue in
                appearance = apply(appearance, newValue)
                appModel.appearanceStore.setAppearance(appearance)
            }
        )
    }
}


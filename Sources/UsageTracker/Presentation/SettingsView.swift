import SwiftUI

struct SettingsView: View {
    @ObservedObject var appModel: AppModel
    let expanded: Provider
    let onBack: () -> Void

    @State private var expandedProviders: Set<Provider>
    @State private var appearance: MenuBarAppearance
    @State private var interval: RefreshInterval

    init(appModel: AppModel, expanded: Provider, onBack: @escaping () -> Void) {
        self.appModel = appModel
        self.expanded = expanded
        self.onBack = onBack
        _expandedProviders = State(initialValue: [expanded])
        _appearance = State(initialValue: appModel.appearanceStore.appearance())
        _interval = State(initialValue: appModel.intervalStore.interval())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                ForEach(appModel.providers) { provider in
                    providerSection(provider)
                }

                Divider()
                menuBarSection

                Divider()
                refreshSection
            }
            .padding(16)
        }
        .frame(width: PopoverLayout.width)
        .frame(maxHeight: 600)
        .onAppear {
            appearance = appModel.appearanceStore.appearance()
            interval = appModel.intervalStore.interval()
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)
            .help("Back")
            .accessibilityLabel("Back")

            Text("Settings")
                .font(.headline)

            Spacer(minLength: 0)
        }
    }

    private func providerSection(_ provider: ProviderViewModel) -> some View {
        let isExpanded = Binding(
            get: { expandedProviders.contains(provider.id) },
            set: { newValue in
                if newValue {
                    expandedProviders.insert(provider.id)
                } else {
                    expandedProviders.remove(provider.id)
                }
            }
        )

        return DisclosureGroup(isExpanded: isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(provider.descriptor.subscriptionFields + provider.descriptor.apiFields) { field in
                    CredentialFieldView(
                        field: field,
                        key: CredentialKey(provider: provider.id, fieldID: field.id),
                        store: appModel.credentialStore,
                        budgetStore: appModel.budgetStore,
                        onChange: { await appModel.provider(provider.id).credentialsChanged(half: field.half) }
                    )
                }
            }
            .padding(.top, 8)
        } label: {
            Text(provider.descriptor.displayName)
                .font(.subheadline.weight(.semibold))
        }
    }

    private var menuBarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Menu bar")
                .font(.subheadline.weight(.semibold))

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
    }

    @ViewBuilder
    private var preview: some View {
        let provider = appModel.provider(expanded)
        let item = MenuBarItemBuilder.make(
            descriptor: provider.descriptor,
            subscription: provider.subscription.map(HalfSnapshot.init),
            api: provider.api.map(HalfSnapshot.init),
            apiBudget: appModel.budgetStore.budget(for: expanded),
            now: Date()
        )

        HStack {
            if let item {
                MenuBarLabel(item: item, appearance: appearance, displayName: provider.descriptor.displayName)
            } else {
                Text("No data yet")
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var refreshSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Refresh")
                .font(.subheadline.weight(.semibold))

            Picker("Refresh", selection: Binding(
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
            .labelsHidden()
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

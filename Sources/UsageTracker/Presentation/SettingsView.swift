import SwiftUI

/// Which page is showing and whether a provider's first credential help
/// starts open. Shared between the window controller and the pages.
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

enum SettingsHelp {
    /// The field whose help starts open: the requested provider's first field.
    static func fieldID(for descriptor: ProviderDescriptor, helpProvider: Provider?) -> String? {
        guard descriptor.id == helpProvider else {
            return nil
        }

        return (descriptor.subscriptionFields + descriptor.apiFields).first?.id
    }
}

enum SettingsLayout {
    static let pageWidth: CGFloat = 460
    static let padding: CGFloat = 20
}

/// A titled group of rows on a soft card, the way the popover laid out its settings.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 0, content: content)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
        }
    }
}

/// One labelled row inside a section; rows are separated by hairlines.
struct SettingsRow<Control: View>: View {
    let label: String
    var isLast = false
    @ViewBuilder let control: () -> Control

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                Spacer(minLength: 12)
                control()
            }
            .frame(minHeight: 34)

            if !isLast {
                Divider()
            }
        }
    }
}

struct SwitchToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
    }
}

/// The five appearance rows, used for the global defaults and for a provider's override.
struct MenuBarAppearanceRows: View {
    @Binding var appearance: MenuBarAppearance

    var body: some View {
        SettingsRow(label: "Show text") {
            SwitchToggle(isOn: binding(\.showText) { $0.showingText($1) })
                .disabled(appearance.showText && !appearance.showGraph)
        }
        SettingsRow(label: "Countdown") {
            SwitchToggle(isOn: binding(\.countdown) { var copy = $0; copy.countdown = $1; return copy })
        }
        SettingsRow(label: "Show graph") {
            SwitchToggle(isOn: binding(\.showGraph) { $0.showingGraph($1) })
                .disabled(appearance.showGraph && !appearance.showText)
        }
        SettingsRow(label: "Graph style") {
            Picker("Graph style", selection: binding(\.graphStyle) { var copy = $0; copy.graphStyle = $1; return copy }) {
                ForEach(MenuBarGraphStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        SettingsRow(label: "Colored", isLast: true) {
            SwitchToggle(isOn: binding(\.colored) { var copy = $0; copy.colored = $1; return copy })
        }
    }

    /// Reads one property and writes through `apply`, which may refuse a change.
    private func binding<Value>(
        _ keyPath: KeyPath<MenuBarAppearance, Value>,
        apply: @escaping (MenuBarAppearance, Value) -> MenuBarAppearance
    ) -> Binding<Value> {
        Binding(
            get: { appearance[keyPath: keyPath] },
            set: { appearance = apply(appearance, $0) }
        )
    }
}

struct RefreshIntervalPicker: View {
    @Binding var interval: RefreshInterval

    var body: some View {
        Picker("Every", selection: $interval) {
            ForEach(RefreshInterval.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

/// The menu bar item for `provider` as it would render with `appearance`.
@MainActor
func previewItem(for provider: ProviderViewModel, in appModel: AppModel) -> MenuBarItem? {
    MenuBarItemBuilder.make(
        descriptor: provider.descriptor,
        subscription: provider.subscription.map(HalfSnapshot.init),
        api: provider.api.map(HalfSnapshot.init),
        apiBudget: appModel.budgetStore.budget(for: provider.id),
        now: Date()
    )
}

struct ProviderSettingsView: View {
    @ObservedObject var provider: ProviderViewModel
    @ObservedObject var appModel: AppModel
    let helpFieldID: String?

    private var settings: Binding<ProviderSettings> {
        Binding(
            get: { appModel.settings(for: provider.id) },
            set: { appModel.setSettings($0, for: provider.id) }
        )
    }

    private var status: ProviderStatus {
        let halves = [provider.subscription, provider.api].compactMap { $0 }
        return ProviderStatus.make(
            configured: provider.isConfigured,
            enabled: provider.isEnabled,
            statuses: halves.map(\.status),
            planName: halves.compactMap { $0.report?.planName }.first
        )
    }

    private var usesCustomAppearance: Binding<Bool> {
        Binding(
            get: { settings.wrappedValue.appearanceOverride != nil },
            set: { settings.wrappedValue.appearanceOverride = $0 ? appModel.globalAppearance : nil }
        )
    }

    private var overrideAppearance: Binding<MenuBarAppearance> {
        Binding(
            get: { settings.wrappedValue.appearanceOverride ?? appModel.globalAppearance },
            set: { settings.wrappedValue.appearanceOverride = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProviderStatusHeader(
                provider: provider.id,
                displayName: provider.descriptor.displayName,
                status: status,
                updatedText: provider.isConfigured ? PopoverPresentation.updatedText(provider.updatedAt) : nil,
                isEnabled: provider.isConfigured ? settings.isEnabled : nil
            )

            if provider.isConfigured, !provider.isEnabled {
                Text("Turn the provider on to see its settings. Its credentials are kept.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                sections
            }
        }
        .padding(SettingsLayout.padding)
        .frame(width: SettingsLayout.pageWidth)
        .fixedSize(horizontal: false, vertical: true)
        // Stays at the top while the window animates to the new height.
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var sections: some View {
        Group {
            SettingsSection(title: "Credentials") {
                let fields = provider.descriptor.subscriptionFields + provider.descriptor.apiFields
                ForEach(fields) { field in
                    CredentialFieldView(
                        field: field,
                        key: CredentialKey(provider: provider.id, fieldID: field.id),
                        store: appModel.credentialStore,
                        budgetStore: appModel.budgetStore,
                        opensHelp: field.id == helpFieldID,
                        onChange: { await appModel.provider(provider.id).credentialsChanged(half: field.half) }
                    )
                    .padding(.vertical, 12)

                    if field.id != fields.last?.id {
                        Divider()
                    }
                }
            }

            Text("Stored only in your login Keychain. Nothing leaves this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)

            SettingsSection(title: "Refresh") {
                SettingsRow(label: "Every", isLast: true) {
                    RefreshIntervalPicker(interval: settings.refreshInterval)
                }
            }

            SettingsSection(title: "Menu bar") {
                SettingsRow(label: "Custom appearance", isLast: !usesCustomAppearance.wrappedValue) {
                    SwitchToggle(isOn: usesCustomAppearance)
                }

                if usesCustomAppearance.wrappedValue {
                    MenuBarPreviewStrip(
                        item: previewItem(for: provider, in: appModel),
                        appearance: overrideAppearance.wrappedValue,
                        displayName: provider.descriptor.displayName,
                        caption: "This provider's item with its own settings."
                    )
                    .padding(.vertical, 10)

                    Divider()
                    MenuBarAppearanceRows(appearance: overrideAppearance)
                }
            }

            Text(usesCustomAppearance.wrappedValue
                 ? "These settings apply to this provider only."
                 : "Follows the defaults on the General tab.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var appModel: AppModel

    private var appearance: Binding<MenuBarAppearance> {
        Binding(
            get: { appModel.globalAppearance },
            set: { appModel.setGlobalAppearance($0) }
        )
    }

    /// The enabled, configured provider shown in the preview, else the first enabled one with
    /// something to fetch; disabled providers have no item to preview.
    static func previewProvider(from providers: [ProviderViewModel]) -> ProviderViewModel? {
        let enabled = providers.filter(\.isEnabled)
        return enabled.first(where: \.isConfigured) ?? enabled.first(where: \.hasAnyHalf)
    }

    private var previewProvider: ProviderViewModel? {
        Self.previewProvider(from: appModel.providers)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MenuBarPreviewStrip(
                item: previewProvider.flatMap { previewItem(for: $0, in: appModel) },
                appearance: appearance.wrappedValue,
                displayName: previewProvider?.descriptor.displayName ?? "",
                placeholder: previewProvider == nil ? "No provider enabled" : "No data yet"
            )

            SettingsSection(title: "Menu bar") {
                MenuBarAppearanceRows(appearance: appearance)
            }

            Text("Defaults for every provider. A provider's tab can override them and sets its own refresh rate. Colored tints the item by remaining capacity or pacing.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(SettingsLayout.padding)
        .frame(width: SettingsLayout.pageWidth)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

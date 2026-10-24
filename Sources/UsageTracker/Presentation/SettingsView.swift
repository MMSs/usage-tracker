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

struct ProviderSettingsView: View {
    @ObservedObject var provider: ProviderViewModel
    let appModel: AppModel
    let helpFieldID: String?

    private var status: ProviderStatus {
        let halves = [provider.subscription, provider.api].compactMap { $0 }
        return ProviderStatus.make(
            configured: provider.isConfigured,
            statuses: halves.map(\.status),
            planName: halves.compactMap { $0.report?.planName }.first
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProviderStatusHeader(
                provider: provider.id,
                displayName: provider.descriptor.displayName,
                status: status,
                updatedText: provider.isConfigured ? PopoverPresentation.updatedText(provider.updatedAt) : nil
            )

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
        }
        .padding(SettingsLayout.padding)
        .frame(width: SettingsLayout.pageWidth)
        .fixedSize(horizontal: false, vertical: true)
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
        VStack(alignment: .leading, spacing: 16) {
            MenuBarPreviewStrip(item: previewItem, appearance: appearance, displayName: previewProvider?.descriptor.displayName ?? "")

            SettingsSection(title: "Menu bar") {
                SettingsRow(label: "Show text") {
                    switchToggle(binding(\.showText) { $0.showingText($1) })
                        .disabled(appearance.showText && !appearance.showGraph)
                }
                SettingsRow(label: "Countdown") {
                    switchToggle(binding(\.countdown) { var copy = $0; copy.countdown = $1; return copy })
                }
                SettingsRow(label: "Show graph") {
                    switchToggle(binding(\.showGraph) { $0.showingGraph($1) })
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
                    switchToggle(binding(\.colored) { var copy = $0; copy.colored = $1; return copy })
                }
            }

            SettingsSection(title: "Refresh") {
                SettingsRow(label: "Every", isLast: true) {
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
                    .labelsHidden()
                    .fixedSize()
                }
            }

            Text("Refreshing pauses while the Mac is asleep or offline. Colored tints the item by remaining capacity or pacing.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(SettingsLayout.padding)
        .frame(width: SettingsLayout.pageWidth)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            appearance = appModel.appearanceStore.appearance()
            interval = appModel.intervalStore.interval()
        }
    }

    private func switchToggle(_ isOn: Binding<Bool>) -> some View {
        Toggle("", isOn: isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
    }

    /// The configured provider shown in the preview, else the first listed one.
    private var previewProvider: ProviderViewModel? {
        appModel.providers.first(where: \.isConfigured) ?? appModel.providers.first(where: \.hasAnyHalf)
    }

    private var previewItem: MenuBarItem? {
        previewProvider.flatMap { provider in
            MenuBarItemBuilder.make(
                descriptor: provider.descriptor,
                subscription: provider.subscription.map(HalfSnapshot.init),
                api: provider.api.map(HalfSnapshot.init),
                apiBudget: appModel.budgetStore.budget(for: provider.id),
                now: Date()
            )
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

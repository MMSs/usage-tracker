import SwiftUI

/// Which page is showing, each provider page's tab, and whether a provider's
/// first credential help starts open. Shared between the window controller
/// and the pages.
@MainActor
final class SettingsSelection: ObservableObject {
    @Published var page: SettingsPage = .general
    /// The provider whose first credential help starts open, until the user leaves its page or tab.
    @Published var helpProvider: Provider?
    /// The tab each provider page shows; absent means its first tab. Kept for one window.
    @Published var tabs: [Provider: ProviderSettingsTab] = [:]

    func apply(_ request: SettingsRequest, listed: [Provider]) {
        page = SettingsPage.resolve(request, listed: listed)
        helpProvider = request.opensHelp ? request.provider : nil

        // The help opens on a field, so show the tab that holds it.
        if request.opensHelp, let provider = request.provider, page == .provider(provider),
           let tab = SettingsHelp.tab(for: ProviderRegistry.descriptor(for: provider), helpProvider: provider) {
            tabs[provider] = tab
        }
    }

    /// The user picked a tab; the help requested for that page stays closed from here on.
    func selectTab(_ tab: ProviderSettingsTab, for provider: Provider) {
        tabs[provider] = tab
        if helpProvider == provider {
            helpProvider = nil
        }
    }
}

/// The segments under a provider page's status header.
enum ProviderSettingsTab: Hashable {
    case subscription, api, menuBar

    init(_ half: Half) {
        switch half {
        case .subscription: self = .subscription
        case .api: self = .api
        }
    }

    var title: String {
        switch self {
        case .subscription: "Subscription"
        case .api: "API usage"
        case .menuBar: "Options"
        }
    }

    /// One tab per half the provider has, then Menu bar.
    @MainActor
    static func tabs(for provider: ProviderViewModel) -> [ProviderSettingsTab] {
        [Half.subscription, .api].filter { provider.half($0) != nil }.map(ProviderSettingsTab.init) + [.menuBar]
    }

    /// The tab that shows the field: its half's.
    static func holding(fieldID: String, in descriptor: ProviderDescriptor) -> ProviderSettingsTab? {
        descriptor.fields.first { $0.id == fieldID }.map { ProviderSettingsTab($0.half) }
    }

    /// The chosen tab when the page has it, else the page's first.
    static func resolve(_ tab: ProviderSettingsTab?, in tabs: [ProviderSettingsTab]) -> ProviderSettingsTab {
        if let tab, tabs.contains(tab) {
            return tab
        }

        return tabs.first ?? .menuBar
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

    /// The tab holding that field, which a help request selects.
    static func tab(for descriptor: ProviderDescriptor, helpProvider: Provider?) -> ProviderSettingsTab? {
        fieldID(for: descriptor, helpProvider: helpProvider).flatMap { ProviderSettingsTab.holding(fieldID: $0, in: descriptor) }
    }
}

enum SettingsLayout {
    static let pageWidth: CGFloat = 460
    static let padding: CGFloat = 20
}

/// Lays out one settings page at the fixed width and reports its laid-out
/// height, so the window can follow it the moment content appears or goes.
struct SettingsPageLayout<Content: View>: View {
    let reportHeight: (CGFloat) -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(SettingsLayout.padding)
            .frame(width: SettingsLayout.pageWidth)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                reportHeight(height)
            }
            // Stays at the top while the window animates to the new height.
            .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// A titled group of rows on a soft card, the way the popover laid out its settings.
struct SettingsSection<Content: View>: View {
    /// Nil leaves the card untitled, under a tab that already names it.
    let title: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.headline)
            }

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

/// The appearance rows, used for the global defaults and for a provider's override.
/// The half switches show only where both halves exist; Limits names the provider's windows.
struct MenuBarAppearanceRows: View {
    @Binding var appearance: MenuBarAppearance
    let meterNames: MeterNames?
    let showsHalfSwitches: Bool

    var body: some View {
        SettingsRow(label: "Show text") {
            SwitchToggle(isOn: binding(\.showText) { $0.showingText($1) })
                .disabled(appearance.showText && !appearance.countdown && !appearance.showGraph)
        }
        SettingsRow(label: "Countdown") {
            SwitchToggle(isOn: binding(\.countdown) { $0.showingCountdown($1) })
                .disabled(appearance.countdown && !appearance.showText && !appearance.showGraph)
        }
        SettingsRow(label: "Show graph") {
            SwitchToggle(isOn: binding(\.showGraph) { $0.showingGraph($1) })
                .disabled(appearance.showGraph && !appearance.showText && !appearance.countdown)
        }
        SettingsRow(label: "Graph style") {
            Picker("Graph style", selection: binding(\.graphStyle) { var copy = $0; copy.graphStyle = $1; return copy }) {
                ForEach(MenuBarGraphStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        }
        SettingsRow(label: "Colored") {
            SwitchToggle(isOn: binding(\.colored) { var copy = $0; copy.colored = $1; return copy })
        }
        if showsHalfSwitches {
            SettingsRow(label: "Show plan usage") {
                SwitchToggle(isOn: binding(\.showPlanUsage) { $0.showingPlanUsage($1) })
                    .disabled(appearance.showPlanUsage && !appearance.showAPISpend)
            }
            SettingsRow(label: "Show API spend") {
                SwitchToggle(isOn: binding(\.showAPISpend) { $0.showingAPISpend($1) })
                    .disabled(appearance.showAPISpend && !appearance.showPlanUsage)
            }
        }
        SettingsRow(label: "Limits", isLast: true) {
            Picker("Limits", selection: binding(\.limits) { var copy = $0; copy.limits = $1; return copy }) {
                ForEach(MenuBarLimits.allCases) { limits in
                    Text(limits.title(names: meterNames)).tag(limits)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
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

/// A stepped slider over the refresh intervals with the chosen value beside it.
struct RefreshIntervalSlider: View {
    @Binding var interval: RefreshInterval

    private var step: Binding<Double> {
        Binding(
            get: { Double(interval.step) },
            set: { interval = RefreshInterval.at(step: $0) }
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            Slider(value: step, in: 0 ... Double(RefreshInterval.allCases.count - 1), step: 1)
                .frame(width: 220)
                .accessibilityLabel("Refresh interval")
                .accessibilityValue(interval.title)

            Text(interval.title)
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)
        }
    }
}

/// The menu bar item for `provider` as it would render with `appearance`.
@MainActor
func previewItem(for provider: ProviderViewModel, in appModel: AppModel) -> MenuBarItem? {
    let now = Date()
    return MenuBarItemBuilder.make(
        descriptor: provider.descriptor,
        subscription: provider.snapshot(.subscription),
        api: provider.snapshot(.api),
        apiBudget: appModel.budget(for: provider.id),
        now: now,
        history: provider.usageHistory(now: now)
    )
}

struct ProviderSettingsView: View {
    @ObservedObject var provider: ProviderViewModel
    @ObservedObject var appModel: AppModel
    let helpFieldID: String?
    /// The chosen tab; nil, or one the page lacks, shows the first.
    @Binding var tab: ProviderSettingsTab?

    private var settings: Binding<ProviderSettings> {
        Binding(
            get: { appModel.settings(for: provider.id) },
            set: { appModel.setSettings($0, for: provider.id) }
        )
    }

    private var status: ProviderStatus {
        ProviderStatus.make(for: provider, item: previewItem(for: provider, in: appModel))
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
    }

    private func halfEnabled(_ half: Half) -> Binding<Bool> {
        Binding(
            get: { settings.wrappedValue.isEnabled(half) },
            set: { settings.wrappedValue.setEnabled($0, for: half) }
        )
    }

    private var alertsEnabled: Binding<Bool> {
        Binding(
            get: { settings.wrappedValue.alertsEnabled },
            set: { settings.wrappedValue.alertsEnabled = $0 }
        )
    }

    private var autoStartSessions: Binding<Bool> {
        Binding(
            get: { settings.wrappedValue.autoStartSessions },
            set: { settings.wrappedValue.autoStartSessions = $0 }
        )
    }

    private var tabs: [ProviderSettingsTab] {
        ProviderSettingsTab.tabs(for: provider)
    }

    private var selectedTab: Binding<ProviderSettingsTab> {
        Binding(
            get: { ProviderSettingsTab.resolve(tab, in: tabs) },
            set: { tab = $0 }
        )
    }

    @ViewBuilder
    private var sections: some View {
        Picker("Section", selection: selectedTab) {
            ForEach(tabs, id: \.self) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity)

        switch selectedTab.wrappedValue {
        case .subscription:
            credentialTab(.subscription)
        case .api:
            credentialTab(.api)
        case .menuBar:
            menuBarTab
        }
    }

    /// A half's section with the Keychain note under it.
    private func credentialTab(_ half: Half) -> some View {
        Group {
            halfSection(half)

            Text("Credentials are stored only in your login Keychain. Nothing leaves this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var menuBarTab: some View {
        SettingsSection(title: "Alerts") {
            SettingsRow(label: "Notify at 80% and 95%", isLast: true) {
                SwitchToggle(isOn: alertsEnabled)
                    .disabled(!appModel.alertsEnabled)
            }
        }

        if !appModel.alertsEnabled {
            Text("Alerts are off on the General tab.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        SettingsSection(title: "Refresh") {
            SettingsRow(label: "Every", isLast: true) {
                RefreshIntervalSlider(interval: settings.refreshInterval)
            }
        }

        SettingsSection(title: "Appearance") {
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
                MenuBarAppearanceRows(
                    appearance: overrideAppearance,
                    meterNames: provider.descriptor.meterNames,
                    showsHalfSwitches: provider.descriptor.capabilities.hasSubscription
                        && provider.descriptor.capabilities.hasAPISpend
                )
            }
        }

        Text(usesCustomAppearance.wrappedValue
             ? "These settings apply to this provider only."
             : "Follows the defaults on the General tab.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// One half's switch and, while it is on, its credential fields. Untitled: the tab names it.
    @ViewBuilder
    private func halfSection(_ half: Half) -> some View {
        let enabled = halfEnabled(half)
        let fields = half == .subscription ? provider.descriptor.subscriptionFields : provider.descriptor.apiFields
        let offersAutoStart = half == .subscription
            && provider.descriptor.capabilities.canStartSession
            && provider.subscription?.canStartSession == true

        SettingsSection(title: nil) {
            SettingsRow(label: "Enabled", isLast: !enabled.wrappedValue) {
                SwitchToggle(isOn: enabled)
            }

            if enabled.wrappedValue {
                ForEach(fields) { field in
                    CredentialFieldView(
                        field: field,
                        key: CredentialKey(provider: provider.id, fieldID: field.id),
                        store: appModel.credentialStore,
                        budget: appModel.budget(for: provider.id),
                        onBudgetChange: { appModel.setBudget($0, for: provider.id) },
                        opensHelp: field.id == helpFieldID,
                        onChange: { await appModel.provider(provider.id).credentialsChanged(half: field.half) }
                    )
                    .padding(.vertical, 12)

                    if field.id != fields.last?.id {
                        Divider()
                    }
                }

                if let model = provider.half(half), model.offersOrganizationChoice {
                    Divider()
                    OrganizationPickerRow(half: model)
                }

                if offersAutoStart {
                    Divider()
                    SettingsRow(label: "Auto-start sessions", isLast: true) {
                        SwitchToggle(isOn: autoStartSessions)
                    }
                }
            }
        }

        if offersAutoStart, enabled.wrappedValue {
            Text("Sends a one-word message to start the 5-hour window as soon as the previous one ends.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// The Organization row under a half's credential while it sees several.
/// Choosing one stores it and refreshes the half.
struct OrganizationPickerRow: View {
    @ObservedObject var half: HalfViewModel

    /// Wide enough for "<email>'s Organization · Max 20x"; longer labels
    /// are cut in the middle by the pop-up button.
    static let pickerMaxWidth: CGFloat = 250

    private var selection: Binding<String?> {
        Binding(
            get: { half.chosenOrganization?.id },
            set: { id in
                guard let id else {
                    return
                }

                Task { await half.selectOrganization(id) }
            }
        )
    }

    var body: some View {
        let labels = AccountOrganization.labels(for: half.organizations)

        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(label: "Organization", isLast: true) {
                Picker("Organization", selection: selection) {
                    // Until one is chosen (or after the chosen one left the list).
                    if half.chosenOrganization == nil {
                        Text("Choose…").tag(String?.none)
                    }

                    ForEach(half.organizations) { organization in
                        Text(labels[organization.id] ?? organization.title).tag(Optional(organization.id))
                    }
                }
                .labelsHidden()
                .truncationMode(.middle)
                .frame(maxWidth: Self.pickerMaxWidth, alignment: .trailing)
            }

            if half.chosenOrganization == nil {
                Text("\(half.half.displayName) is fetched once you choose an organization.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 10)
            }
        }
    }
}

/// The Open at login switch with the live macOS status under it. Re-reads the
/// status when the page appears and when the app comes back from System Settings.
struct OpenAtLoginRows: View {
    @ObservedObject var loginItem: LoginItemModel

    private var isOn: Binding<Bool> {
        Binding(get: { loginItem.isOn }, set: { loginItem.setOn($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(label: "Open at login", isLast: loginItem.statusLine == nil) {
                SwitchToggle(isOn: isOn)
            }

            if let line = loginItem.statusLine {
                HStack {
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    if loginItem.needsApproval {
                        Button("Open System Settings") { loginItem.openSystemSettings() }
                            .controlSize(.small)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
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

    private var alertsEnabled: Binding<Bool> {
        Binding(
            get: { appModel.alertsEnabled },
            set: { appModel.setAlertsEnabled($0) }
        )
    }

    /// The providers whose items the menu bar shows, left to right as they
    /// appear on screen (`AppModel.menuBarDisplayOrder`). None while the menu
    /// bar holds only the set-up item.
    static func previewProviders(in appModel: AppModel) -> [ProviderViewModel] {
        guard !appModel.showsSetUpItem else {
            return []
        }

        return AppModel.menuBarDisplayOrder(appModel.insertedProviders).map(appModel.provider)
    }

    /// Each item as the menu bar draws it, with its provider's override if it has one.
    private var previewEntries: [MenuBarPreviewStrip.Entry] {
        Self.previewProviders(in: appModel).map { provider in
            MenuBarPreviewStrip.Entry(
                item: previewItem(for: provider, in: appModel)
                    ?? MenuBarItem(provider: provider.id, subscription: .status(.loading), api: nil),
                appearance: appModel.appearance(for: provider.id),
                displayName: provider.descriptor.displayName
            )
        }
    }

    /// Disabled providers have no item to preview.
    private var placeholder: String {
        appModel.providers.contains { $0.isEnabled && $0.hasAnyHalf } ? "No data yet" : "No provider enabled"
    }

    var body: some View {
        let entries = previewEntries

        VStack(alignment: .leading, spacing: 16) {
            MenuBarPreviewStrip(
                entries: entries,
                caption: entries.count > 1 ? "How the items look in the menu bar." : "How the item looks in the menu bar.",
                placeholder: placeholder
            )

            SettingsSection(title: "Menu bar") {
                MenuBarAppearanceRows(appearance: appearance, meterNames: nil, showsHalfSwitches: true)
            }

            SettingsSection(title: "Alerts") {
                SettingsRow(label: "Usage alerts", isLast: true) {
                    SwitchToggle(isOn: alertsEnabled)
                }
            }

            Text("Notifies when a limit or an API budget reaches 80% and 95%.")
                .font(.caption)
                .foregroundStyle(.secondary)

            SettingsSection(title: "Startup") {
                OpenAtLoginRows(loginItem: appModel.loginItem)
            }

            Text("Defaults for every provider. A provider's tab can override them and sets its own refresh rate. Colored tints the item by remaining capacity or pacing. Show plan usage and Show API spend hide a half from the item; the popover still lists it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

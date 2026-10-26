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
    /// The titled section open on each provider page's tab; absent means its first.
    @Published var openSections: [Provider: String] = [:]

    func apply(_ request: SettingsRequest, listed: [Provider]) {
        page = SettingsPage.resolve(request, listed: listed)
        helpProvider = request.opensHelp ? request.provider : nil

        // The help opens on a field, so show the tab that holds it.
        if request.opensHelp, let provider = request.provider, page == .provider(provider),
           let tab = SettingsHelp.tab(for: ProviderRegistry.descriptor(for: provider), helpProvider: provider) {
            tabs[provider] = tab
        }
    }

    /// The user picked a tab; it opens on its first section, and the help
    /// requested for that page stays closed from here on.
    func selectTab(_ tab: ProviderSettingsTab, for provider: Provider) {
        tabs[provider] = tab
        openSections[provider] = nil
        if helpProvider == provider {
            helpProvider = nil
        }
    }

    /// The provider's page on the tab holding its Custom appearance switch, with that section open.
    func showAppearance(of provider: Provider) {
        page = .provider(provider)
        helpProvider = nil
        tabs[provider] = .menuBar
        openSections[provider] = "Appearance"
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

    /// The titled sections the tab shows, in order. A half's untitled switch and credential section comes first.
    var sections: [String] {
        switch self {
        case .subscription, .api: ["Schedule"]
        case .menuBar: ["Alerts", "Appearance"]
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
/// With an accordion in the environment a titled section folds: its header opens it
/// and its rows and footer show only while it is open.
struct SettingsSection<Content: View>: View {
    /// Nil leaves the card untitled, under a tab that already names it.
    let title: String?
    /// A caption under the card that hides with it.
    var footer: String?
    @ViewBuilder let content: () -> Content

    @Environment(\.settingsAccordion) private var accordion

    private var isOpen: Bool {
        guard let title, let accordion else {
            return true
        }

        return accordion.wrappedValue.isOpen(title)
    }

    private var isCollapsible: Bool {
        title != nil && accordion?.wrappedValue.isCollapsible == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                header(title)
            }

            // Layout never animates: the window snaps to the new height on
            // the next turn, and sections sliding meanwhile would fight it.
            // Only the opened section's rows fade in.
            if isOpen {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 0, content: content)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )

                    if let footer {
                        Text(footer)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .modifier(FadesIn(enabled: isCollapsible))
            }
        }
    }

    /// A button that opens the section when it folds; otherwise a plain heading.
    @ViewBuilder
    private func header(_ title: String) -> some View {
        if isCollapsible {
            Button {
                accordion?.wrappedValue.open(title)
            } label: {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer(minLength: 12)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        // Scoped to the turn, so the chevron never animates its position.
                        .animation(.easeInOut(duration: 0.2)) { $0.rotationEffect(.degrees(isOpen ? 90 : 0)) }
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
        } else {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/// Fades a section's rows in when it opens. Opacity only, so nothing the
/// window's height follows ever moves.
private struct FadesIn: ViewModifier {
    let enabled: Bool
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(!enabled || shown ? 1 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: 0.15)) {
                    shown = true
                }
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

/// A provider listed under General's appearance defaults because it has its
/// own: the name opens its appearance settings, Use Defaults drops them.
struct CustomAppearanceRow: View {
    let name: String
    var isLast = false
    let show: () -> Void
    let useDefaults: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button(name, action: show)
                    .buttonStyle(.link)
                    .help("Open \(name)'s appearance settings")
                Text("uses a custom appearance")
                Spacer(minLength: 12)
                Button("Use Defaults", action: useDefaults)
                    .controlSize(.small)
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
/// Limits names the provider's windows.
struct MenuBarAppearanceRows: View {
    @Binding var appearance: MenuBarAppearance
    let meterNames: MeterNames?

    var body: some View {
        SettingsRow(label: "Show text") {
            SwitchToggle(isOn: binding(\.showText) { var copy = $0; copy.showText = $1; return copy })
        }
        SettingsRow(label: "Countdown") {
            SwitchToggle(isOn: binding(\.countdown) { var copy = $0; copy.countdown = $1; return copy })
        }
        SettingsRow(label: "Show graph") {
            SwitchToggle(isOn: binding(\.showGraph) { var copy = $0; copy.showGraph = $1; return copy })
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
    MenuBarItemBuilder.make(
        descriptor: provider.descriptor,
        subscription: provider.snapshot(.subscription),
        api: provider.snapshot(.api),
        apiBudget: appModel.budget(for: provider.id),
        now: Date()
    )
}

struct ProviderSettingsView: View {
    @ObservedObject var provider: ProviderViewModel
    @ObservedObject var appModel: AppModel
    let helpFieldID: String?
    /// The chosen tab; nil, or one the page lacks, shows the first.
    @Binding var tab: ProviderSettingsTab?
    /// Which of the tab's titled sections is open; nil, or one the tab lacks, opens its first.
    @Binding var openSection: String?

    private var accordion: Binding<SettingsAccordion> {
        let titles = selectedTab.wrappedValue.sections
        return Binding(
            get: { SettingsAccordion(titles: titles, open: openSection) },
            set: { openSection = $0.open }
        )
    }

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

    private func refreshInterval(_ half: Half) -> Binding<RefreshInterval> {
        Binding(
            get: { settings.wrappedValue.refreshInterval(for: half) },
            set: { settings.wrappedValue.setRefreshInterval($0, for: half) }
        )
    }

    private func halfEnabled(_ half: Half) -> Binding<Bool> {
        Binding(
            get: { settings.wrappedValue.isEnabled(half) },
            set: { settings.wrappedValue.setEnabled($0, for: half) }
        )
    }

    private func showsInMenuBar(_ half: Half) -> Binding<Bool> {
        Binding(
            get: { settings.wrappedValue.showsInMenuBar(half) },
            set: { settings.wrappedValue.setShowsInMenuBar($0, for: half) }
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

        Group {
            switch selectedTab.wrappedValue {
            case .subscription:
                credentialTab(.subscription)
            case .api:
                credentialTab(.api)
            case .menuBar:
                menuBarTab
            }
        }
        .environment(\.settingsAccordion, accordion)
    }

    /// A half's section with the Keychain note under it.
    private func credentialTab(_ half: Half) -> some View {
        Group {
            halfSection(half)

            Text("Credentials are stored only in your login Keychain. Nothing leaves this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(ProviderSettingsTab(half).sections, id: \.self) { title in
                section(title, half: half)
            }
        }
    }

    private var menuBarTab: some View {
        ForEach(ProviderSettingsTab.menuBar.sections, id: \.self) { title in
            section(title, half: nil)
        }
    }

    /// The body of one titled section named in `ProviderSettingsTab.sections`.
    @ViewBuilder
    private func section(_ title: String, half: Half?) -> some View {
        switch (title, half) {
        case ("Schedule", let half?):
            let autoStarts = offersAutoStart(half)

            SettingsSection(
                title: title,
                footer: autoStarts
                    ? "Auto-start sends a one-word message to start the 5-hour window as soon as the previous one ends."
                    : nil
            ) {
                SettingsRow(label: "Refresh every", isLast: !autoStarts) {
                    RefreshIntervalSlider(interval: refreshInterval(half))
                        .disabled(!settings.wrappedValue.isEnabled(half))
                }

                if autoStarts {
                    SettingsRow(label: "Auto-start sessions", isLast: true) {
                        SwitchToggle(isOn: autoStartSessions)
                            .disabled(!settings.wrappedValue.isEnabled(half))
                    }
                }
            }
        case ("Alerts", _):
            alertsSection(title)
        case ("Appearance", _):
            appearanceSection(title)
        default:
            EmptyView()
        }
    }

    private func alertsSection(_ title: String) -> some View {
        SettingsSection(title: title, footer: appModel.alertsEnabled ? nil : "Alerts are off on the General tab.") {
            SettingsRow(label: "Alerts", isLast: true) {
                SwitchToggle(isOn: alertsEnabled)
                    .disabled(!appModel.alertsEnabled)
            }
        }
    }

    private func appearanceSection(_ title: String) -> some View {
        SettingsSection(
            title: title,
            footer: usesCustomAppearance.wrappedValue
                ? "These settings apply to this provider only."
                : "Follows the defaults on the General tab."
        ) {
            SettingsRow(label: "Custom appearance", isLast: !usesCustomAppearance.wrappedValue) {
                SwitchToggle(isOn: usesCustomAppearance)
            }

            if usesCustomAppearance.wrappedValue {
                MenuBarPreviewStrip(
                    item: previewItem(for: provider, in: appModel),
                    appearance: overrideAppearance.wrappedValue,
                    halves: appModel.menuBarHalves(for: provider.id),
                    displayName: provider.descriptor.displayName,
                    caption: "This provider's item with its own settings."
                )
                .padding(.vertical, 10)

                Divider()
                MenuBarAppearanceRows(
                    appearance: overrideAppearance,
                    meterNames: provider.descriptor.meterNames
                )
            }
        }
    }

    /// One half's switches and, while it is on, its credential fields. Untitled: the tab names it.
    @ViewBuilder
    private func halfSection(_ half: Half) -> some View {
        let enabled = halfEnabled(half)
        let fields = half == .subscription ? provider.descriptor.subscriptionFields : provider.descriptor.apiFields

        SettingsSection(title: nil) {
            SettingsRow(label: "Enabled", isLast: !enabled.wrappedValue) {
                SwitchToggle(isOn: enabled)
            }

            if enabled.wrappedValue {
                // A hidden half is still fetched, still alerts and still shows in the panel.
                SettingsRow(label: "Show in menu bar") {
                    SwitchToggle(isOn: showsInMenuBar(half))
                }

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

            }
        }
    }

    /// Only a plan-usage half whose provider and fetcher can start a session offers auto-start.
    private func offersAutoStart(_ half: Half) -> Bool {
        half == .subscription
            && provider.descriptor.capabilities.canStartSession
            && provider.subscription?.canStartSession == true
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

struct UpdatesSection: View {
    @ObservedObject var updates: UpdatesModel
    static let checkNowTitle = "Check Now"

    private var isAutomatic: Binding<Bool> {
        Binding(get: { updates.isAutomatic }, set: { updates.setAutomatic($0) })
    }

    var body: some View {
        SettingsSection(title: "Updates", footer: updates.message) {
            if updates.isAvailable {
                SettingsRow(label: "Check automatically") {
                    SwitchToggle(isOn: isAutomatic)
                }

                // The button names itself, so it sits under the switch
                // without a row label repeating it.
                HStack {
                    Spacer()
                    Button(Self.checkNowTitle) { updates.checkNow() }
                        .controlSize(.small)
                        .disabled(!updates.canCheck)
                }
                .frame(minHeight: 34)
            }

            Button(updates.versionText) {
                AboutPanel.show()
            }
            .buttonStyle(.link)
            .font(.caption)
            .padding(.vertical, 8)
        }
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var appModel: AppModel
    static let sectionTitles = ["Menu bar appearance", "Alerts", "Startup", "Updates"]
    /// Opens a listed provider's own appearance settings.
    var showAppearance: (Provider) -> Void = { _ in }

    @State private var accordion = SettingsAccordion(titles: GeneralSettingsView.sectionTitles)

    private var appearance: Binding<MenuBarAppearance> {
        Binding(
            get: { appModel.globalAppearance },
            set: { appModel.setGlobalAppearance($0) }
        )
    }

    private func alertKind(_ kind: AlertKind) -> Binding<Bool> {
        Binding(
            get: { appModel.alertKinds.contains(kind) },
            set: { appModel.setAlertKind(kind, enabled: $0) }
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

    /// The previewed items whose provider has its own appearance, in the same
    /// order, so the defaults above don't silently skip them.
    static func customAppearanceProviders(in appModel: AppModel) -> [ProviderViewModel] {
        previewProviders(in: appModel).filter { appModel.settings(for: $0.id).appearanceOverride != nil }
    }

    static func appearanceFooter(listsCustom: Bool) -> String {
        let scope = listsCustom
            ? "Defaults for every provider except those listed above. A provider's tab sets its own refresh rates."
            : "Defaults for every provider. A provider's tab can override them and sets its own refresh rates."
        return scope + " Colored tints the item by remaining capacity or pacing."
    }

    /// Each item as the menu bar draws it, with its provider's override if it has one.
    private var previewEntries: [MenuBarPreviewStrip.Entry] {
        Self.previewProviders(in: appModel).map { provider in
            MenuBarPreviewStrip.Entry(
                item: previewItem(for: provider, in: appModel)
                    ?? MenuBarItem(provider: provider.id, subscription: .status(.loading), api: nil),
                appearance: appModel.appearance(for: provider.id),
                halves: appModel.menuBarHalves(for: provider.id),
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
        let custom = Self.customAppearanceProviders(in: appModel)

        VStack(alignment: .leading, spacing: 16) {
            MenuBarPreviewStrip(
                entries: entries,
                caption: entries.count > 1 ? "How the items look in the menu bar." : "How the item looks in the menu bar.",
                placeholder: placeholder
            )

            SettingsSection(
                title: "Menu bar appearance",
                footer: Self.appearanceFooter(listsCustom: !custom.isEmpty)
            ) {
                MenuBarAppearanceRows(appearance: appearance, meterNames: nil)

                if !custom.isEmpty {
                    Divider()

                    ForEach(custom, id: \.id) { provider in
                        CustomAppearanceRow(
                            name: provider.descriptor.displayName,
                            isLast: provider.id == custom.last?.id,
                            show: { showAppearance(provider.id) },
                            useDefaults: { appModel.useDefaultAppearance(for: provider.id) }
                        )
                    }
                }
            }

            SettingsSection(
                title: "Alerts",
                footer: "Usage thresholds notify at 80% and 95% of a limit or API budget. Session notifies when a 5-hour session resets. Refresh failures notify when a refresh fails for a reason other than the network being down."
            ) {
                SettingsRow(label: "Alerts") {
                    SwitchToggle(isOn: alertsEnabled)
                }

                ForEach(AlertKind.allCases, id: \.self) { kind in
                    SettingsRow(label: kind.title, isLast: kind == AlertKind.allCases.last) {
                        SwitchToggle(isOn: alertKind(kind))
                            .disabled(!appModel.alertsEnabled)
                    }
                }
            }

            SettingsSection(title: "Startup") {
                OpenAtLoginRows(loginItem: appModel.loginItem)
            }

            UpdatesSection(updates: appModel.updates)
        }
        .environment(\.settingsAccordion, $accordion)
    }
}

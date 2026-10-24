import AppKit
import SwiftUI

struct ProviderPopoverView: View {
    @ObservedObject var provider: ProviderViewModel
    let appModel: AppModel
    @State private var escapeMonitor = EscapeMonitorState()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        reportPage
        .frame(width: PopoverLayout.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(HostingWindowReader(onWindow: { window in
            escapeMonitor.window = window
            PopoverWindowAnimator.install(on: window)
        }))
        .onAppear(perform: installEscapeMonitor)
        .onDisappear(perform: removeEscapeMonitor)
    }

    // MARK: - Report page

    private var reportPage: some View {
        let now = Date()

        guard provider.isConfigured else {
            return AnyView(setUpPage)
        }

        // The menu bar item, so a half it marks as failed is explained here.
        let item = MenuBarItemBuilder.make(
            descriptor: provider.descriptor,
            subscription: provider.snapshot(.subscription),
            api: provider.snapshot(.api),
            apiBudget: appModel.budget(for: provider.id),
            now: now
        )

        return AnyView(VStack(alignment: .leading, spacing: 14) {
            header

            if let half = provider.subscription, half.isActive {
                subscriptionSection(half, display: item?.subscription, now: now)
            }

            if let half = provider.api, half.isActive {
                apiSection(half, display: item?.api, now: now)
            }

            footer
        }
        .padding(16))
    }

    private var setUpPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            HStack {
                Button("Set up") {
                    openSettings(opensHelp: true)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)

                Spacer()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q", modifiers: .command)
                .help("Quit")
                .accessibilityLabel("Quit")
            }
        }
        .padding(16)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                ProviderGlyph(provider: provider.id)
                    .fill(.primary)
                    .frame(width: 16, height: 16)
                Text(provider.descriptor.displayName)
                    .font(.headline)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            if let planName = provider.subscription?.report?.planName ?? provider.api?.report?.planName {
                Text(planName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func sectionShell<Content: View>(
        label: String, half: HalfViewModel, display: HalfDisplay?, now: Date, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(label)

            // Shown with or without a report, so the menu bar's error mark always has an explanation.
            if let error = PopoverPresentation.halfError(half, descriptor: provider.descriptor, display: display, now: now) {
                HalfErrorRow(
                    message: error,
                    lastSuccess: half.report == nil ? nil : PopoverPresentation.lastSuccessText(half.lastSuccess, now: now)
                )
            }

            if half.report != nil {
                VStack(alignment: .leading, spacing: 10, content: content)
                    .opacity(half.isStale || half.status == .error || half.status == .expired ? 0.6 : 1)
            } else if half.status == .loading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Loading…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Subscription

    private func subscriptionSection(_ half: HalfViewModel, display: HalfDisplay?, now: Date) -> some View {
        let report = half.report
        let showsCycle = provider.descriptor.capabilities.hasCycle && report?.spend != nil
        let label = showsCycle
            ? "Cycle · " + (PopoverPresentation.headerSubtitle(cycle: report?.spend?.period, planName: report?.planName) ?? "")
            : "Limits"

        return sectionShell(label: label, half: half, display: display, now: now) {
            if let report {
                let pacing = report.spend.flatMap { PacingCalculator.make($0, today: now) }

                ForEach(report.topLevelWindows) { window in
                    limitRow(window, in: report, pacing: pacing, now: now)
                    ForEach(report.children(of: window.id)) { child in
                        let money = report.extra(for: child.id)
                        let childPacing = PopoverPresentation.rowPacing(window: child, now: now)
                        LimitRowView(
                            label: child.label,
                            text: PopoverPresentation.rowText(
                                window: child,
                                money: money,
                                resetText: child.resetsAt == window.resetsAt
                                    ? nil : CountdownFormatter.resetText(resetsAt: child.resetsAt, now: now),
                                daysLeft: nil
                            ),
                            fraction: PopoverPresentation.rowFraction(window: child, money: money),
                            indented: true,
                            tick: childPacing.tick,
                            tint: childPacing.tint
                        )
                    }
                }

                // Extras that match a window are already shown in that window's row.
                ForEach(report.standaloneExtras) { extra in
                    extraRow(extra)
                }

                if let spend = report.spend {
                    if let pacing {
                        PacingView(pacing: pacing, unit: spend.unit, periodEnd: spend.period.end)
                    }

                    if provider.descriptor.capabilities.hasDailyChart, !spend.daily.isEmpty {
                        DailySpendChartView(
                            title: "Daily spend · this cycle", subtitleRow: nil,
                            days: spend.daily, period: spend.period, today: now, unit: spend.unit
                        )
                    }
                }
            }
        }
    }

    private func limitRow(_ window: LimitWindow, in report: ProviderReport, pacing: Pacing?, now: Date) -> some View {
        let isLong = window.id == provider.descriptor.longWindowID
        let isPaced = pacing != nil && isLong
        let money = report.extra(for: window.id)
        // A billing cycle reads better as days left than as a reset date.
        let daysLeft = provider.descriptor.capabilities.hasCycle && isLong
            ? pacing.map(PopoverPresentation.daysLeftText)
            : nil
        let timed = PopoverPresentation.rowPacing(window: window, now: now)

        return LimitRowView(
            label: window.label,
            text: PopoverPresentation.rowText(
                window: window,
                money: money,
                resetText: CountdownFormatter.resetText(resetsAt: window.resetsAt, now: now),
                daysLeft: daysLeft
            ),
            fraction: PopoverPresentation.rowFraction(window: window, money: money),
            indented: false,
            tick: isPaced ? pacing?.tickFraction : timed.tick,
            tint: isPaced ? PacingTint.forPacing(pacing) : timed.tint
        )
    }

    private func extraRow(_ extra: MoneyRow) -> some View {
        let amount = BudgetUnit.dollars.format(extra.amount)
        let text = extra.limit.map { "\(amount) / \(BudgetUnit.dollars.format($0))" } ?? amount

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(extra.label)
                Spacer()
                Text(text)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let limit = extra.limit, limit > 0 {
                let fraction = NSDecimalNumber(decimal: extra.amount / limit).doubleValue
                UsageBar(fraction: fraction, tint: .forRemaining(percentUsed: fraction * 100), height: 5, tick: nil)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: API

    private func apiSection(_ half: HalfViewModel, display: HalfDisplay?, now: Date) -> some View {
        let spend = half.report?.spend
        let month = spend.map { PopoverPresentation.monthName(for: $0.period.start) }
        let label = month.map { "API · \($0)" } ?? "API"
        let budget = PopoverPresentation.effectiveBudget(appModel.budget(for: provider.id))

        return sectionShell(label: label, half: half, display: display, now: now) {
            if let spend {
                let spent = BudgetUnit.dollars.format(spend.spent)
                let pacing = budget.flatMap { PacingCalculator.make(spend, budgetOverride: $0, today: now) }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Spend to date")
                        Spacer()
                        Text(budget.map { "\(spent) / \(BudgetUnit.dollars.format($0))" } ?? spent)
                            .font(.callout.monospacedDigit())
                    }

                    if let budget, budget > 0 {
                        UsageBar(
                            fraction: NSDecimalNumber(decimal: spend.spent / budget).doubleValue,
                            tint: PacingTint.forPacing(pacing), height: 5, tick: pacing?.tickFraction
                        )
                    }
                }
                .accessibilityElement(children: .combine)

                if let pacing {
                    PacingView(pacing: pacing, unit: .dollars, periodEnd: spend.period.end)
                }

                if provider.descriptor.capabilities.hasDailyChart, !spend.daily.isEmpty {
                    DailySpendChartView(
                        title: "Daily spend", subtitleRow: nil,
                        days: spend.daily, period: spend.period, today: now, unit: .dollars
                    )
                }
            }
        }
    }

    // MARK: Footer

    private var isLoading: Bool {
        [provider.subscription, provider.api].contains { $0?.status == .loading }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(PopoverPresentation.updatedText(provider.updatedAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer()

            Button {
                Task { await provider.refresh(manual: true) }
            } label: {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .help("Refresh")
            .accessibilityLabel("Refresh")

            Button {
                openSettings(opensHelp: false)
            } label: {
                Image(systemName: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
            .help("Settings")
            .accessibilityLabel("Settings")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .keyboardShortcut("q", modifiers: .command)
            .help("Quit")
            .accessibilityLabel("Quit")
        }
        .buttonStyle(.plain)
    }

    // MARK: - Window behaviour

    /// Settings lives in its own window, so the popover closes to make way for it.
    private func openSettings(opensHelp: Bool) {
        closePopover()
        appModel.presentSettings(SettingsRequest(provider: provider.id, opensHelp: opensHelp))
    }

    /// The environment action closes a MenuBarExtra window; the status item click is the fallback.
    private func closePopover() {
        dismiss()
        MenuBarPopover.dismiss()
    }

    /// Escape closes the popover.
    private func installEscapeMonitor() {
        removeEscapeMonitor()
        let state = escapeMonitor
        let close = closePopover
        state.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window === state.window, event.keyCode == 53 else { return event }

            DispatchQueue.main.async(execute: close)
            return nil
        }
    }

    private func removeEscapeMonitor() {
        if let monitor = escapeMonitor.monitor {
            NSEvent.removeMonitor(monitor)
        }
        escapeMonitor.monitor = nil
    }
}

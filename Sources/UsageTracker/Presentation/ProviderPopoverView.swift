import AppKit
import SwiftUI

struct ProviderPopoverView: View {
    @ObservedObject var provider: ProviderViewModel
    let appModel: AppModel
    @State private var isSettingsPresented = false
    @State private var escapeMonitor = EscapeMonitorState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if isSettingsPresented {
                SettingsView(appModel: appModel, expanded: provider.id, onBack: { isSettingsPresented = false })
                    .transition(pageTransition(edge: .trailing))
            } else {
                reportPage
                    .transition(pageTransition(edge: .leading))
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: isSettingsPresented)
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

        return VStack(alignment: .leading, spacing: 14) {
            header

            if let half = provider.subscription, half.status != .unconfigured {
                subscriptionSection(half, now: now)
            }

            if let half = provider.api, half.status != .unconfigured {
                apiSection(half, now: now)
            }

            footer
        }
        .padding(16)
    }

    private var header: some View {
        HStack {
            Text(provider.descriptor.displayName)
                .font(.headline)
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
        label: String, half: HalfViewModel, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(label)

            if let error = PopoverPresentation.halfErrorText(half.status) {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private func subscriptionSection(_ half: HalfViewModel, now: Date) -> some View {
        let report = half.report
        let showsCycle = provider.descriptor.capabilities.hasCycle && report?.spend != nil
        let label = showsCycle
            ? "Cycle · " + (PopoverPresentation.headerSubtitle(cycle: report?.spend?.period, planName: report?.planName) ?? "")
            : "Limits"

        return sectionShell(label: label, half: half) {
            if let report {
                let pacing = report.spend.flatMap { PacingCalculator.make($0, today: now) }

                ForEach(report.topLevelWindows) { window in
                    limitRow(window, in: report, pacing: pacing, now: now)
                    ForEach(report.children(of: window.id)) { child in
                        LimitRowView(
                            window: child,
                            resetText: child.resetsAt == window.resetsAt
                                ? nil : CountdownFormatter.resetText(resetsAt: child.resetsAt, now: now),
                            indented: true,
                            tick: nil,
                            tint: PacingTint.forRemaining(percentUsed: child.percentUsed)
                        )
                    }
                }

                ForEach(report.extras) { extra in
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
        let isPaced = pacing != nil && window.id == provider.descriptor.longWindowID
        return LimitRowView(
            window: window,
            resetText: CountdownFormatter.resetText(resetsAt: window.resetsAt, now: now),
            indented: false,
            tick: isPaced ? pacing?.tickFraction : nil,
            tint: isPaced ? PacingTint.forPacing(pacing) : PacingTint.forRemaining(percentUsed: window.percentUsed)
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

    private func apiSection(_ half: HalfViewModel, now: Date) -> some View {
        let spend = half.report?.spend
        let month = spend.map { PopoverPresentation.monthName(for: $0.period.start) }
        let label = month.map { "API · \($0)" } ?? "API"
        let budget = PopoverPresentation.effectiveBudget(appModel.budgetStore.budget(for: provider.id))

        return sectionShell(label: label, half: half) {
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
                        title: label, subtitleRow: nil,
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
                isSettingsPresented = true
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

    private func pageTransition(edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }

    /// Escape steps back from Settings, then closes the popover.
    private func installEscapeMonitor() {
        removeEscapeMonitor()
        let state = escapeMonitor
        state.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window === state.window, event.keyCode == 53 else { return event }

            DispatchQueue.main.async {
                if isSettingsPresented {
                    isSettingsPresented = false
                } else {
                    MenuBarPopover.dismiss()
                }
            }
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

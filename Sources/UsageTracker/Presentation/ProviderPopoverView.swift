import AppKit
import SwiftUI

struct ProviderPopoverView: View {
    @ObservedObject var provider: ProviderViewModel
    @ObservedObject var appModel: AppModel
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
                let history = provider.usageHistory(now: now)

                ForEach(report.topLevelWindows) { window in
                    limitRow(window, in: report, pacing: pacing, history: history[window.id] ?? [], now: now)
                    ForEach(report.children(of: window.id)) { child in
                        let money = report.extra(for: child.id)
                        let childPacing = PopoverPresentation.rowPacing(window: child, now: now)
                        LimitRowView(
                            label: child.label,
                            text: PopoverPresentation.rowText(
                                window: child,
                                money: money,
                                resetText: child.resetsAt == window.resetsAt
                                    ? nil : resetText(for: child, now: now),
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

                // An unlimited cycle has no window row to carry its bars.
                if provider.descriptor.capabilities.hasCycle,
                   !report.topLevelWindows.contains(where: { $0.id == provider.descriptor.longWindowID }),
                   let spend = report.spend, let bars = cycleBars(spend, now: now) {
                    ChartedBarBlock(chartHeight: Self.barsHeight, floor: nil) {
                        DailyBarsChart(bars: bars, showsPaceLine: false, dayLabels: false, unit: spend.unit)
                    }
                }

                sessionControls(half)

                if let spend = report.spend, let pacing {
                    PacingView(pacing: pacing, unit: spend.unit, periodEnd: spend.period.end)
                }
            }
        }
    }

    /// The Start session button while the session is closed (or a start is
    /// running), and a note when the last start failed and it is still closed.
    @ViewBuilder
    private func sessionControls(_ half: HalfViewModel) -> some View {
        let starting = half.sessionStart == .starting

        if provider.sessionIsClosed || starting {
            HStack(spacing: 8) {
                Button("Start session") {
                    Task { await half.startSession() }
                }
                .controlSize(.small)
                .disabled(starting)

                if starting {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }

        if half.sessionStart == .failed, provider.sessionIsClosed {
            Text("Couldn't start session")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private static let sessionHeight: CGFloat = 26
    private static let barsHeight: CGFloat = 30

    /// A window row's chart, as data, so the row knows whether it has one.
    private enum RowChart {
        case session([[CGPoint]])
        case bars([DayBar], showsPaceLine: Bool, dayLabels: Bool, unit: BudgetUnit?)
    }

    @ViewBuilder
    private func limitRow(
        _ window: LimitWindow, in report: ProviderReport, pacing: Pacing?, history: [UsageSample], now: Date
    ) -> some View {
        let isLong = window.id == provider.descriptor.longWindowID
        let isPaced = pacing != nil && isLong
        let money = report.extra(for: window.id)
        // A billing cycle reads better as days left than as a reset date.
        let daysLeft = provider.descriptor.capabilities.hasCycle && isLong
            ? pacing.map(PopoverPresentation.daysLeftText)
            : nil
        let timed = PopoverPresentation.rowPacing(window: window, now: now)
        let text = PopoverPresentation.rowText(
            window: window,
            money: money,
            resetText: resetText(for: window, now: now),
            daysLeft: daysLeft
        )
        let fraction = PopoverPresentation.rowFraction(window: window, money: money)
        let tick = isPaced ? pacing?.tickFraction : timed.tick
        let tint = isPaced ? PacingTint.forPacing(pacing) : timed.tint

        if let chart = rowChart(for: window, in: report, history: history, now: now) {
            VStack(alignment: .leading, spacing: 4) {
                LimitRowLine(label: window.label, text: text, indented: false)
                chartBlock(chart, floor: fraction.map { ChartFloor(fraction: $0, tint: tint, tick: tick) }, tint: tint)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(window.label)
            .accessibilityValue(text)
        } else {
            LimitRowView(label: window.label, text: text, fraction: fraction, indented: false, tick: tick, tint: tint)
        }
    }

    /// Nil, for a plain row, until there is something to draw.
    private func rowChart(for window: LimitWindow, in report: ProviderReport, history: [UsageSample], now: Date) -> RowChart? {
        switch PopoverPresentation.chartKind(for: window, descriptor: provider.descriptor) {
        case .sessionLine:
            let gap = UsageChartLayout.sessionGap(interval: appModel.settings(for: provider.id).refreshInterval(for: .subscription))
            let segments = UsageChartLayout.sessionSegments(
                samples: history, now: now, gap: gap, size: CGSize(width: 1, height: 1)
            )
            return segments.isEmpty ? nil : .session(segments)
        case .weekBars:
            return PopoverPresentation.weekBars(samples: history, window: window, now: now)
                .map { .bars($0, showsPaceLine: true, dayLabels: true, unit: nil) }
        case .cycleBars:
            guard let spend = report.spend, let bars = cycleBars(spend, now: now) else {
                return nil
            }
            return .bars(bars, showsPaceLine: spend.limit != nil, dayLabels: false, unit: spend.unit)
        case nil:
            return nil
        }
    }

    @ViewBuilder
    private func chartBlock(_ chart: RowChart, floor: ChartFloor?, tint: PacingTint) -> some View {
        switch chart {
        case let .session(segments):
            ChartedBarBlock(chartHeight: Self.sessionHeight, floor: floor) {
                SessionHistoryChart(segments: segments, tint: tint)
            }
        case let .bars(bars, showsPaceLine, dayLabels, unit):
            ChartedBarBlock(chartHeight: Self.barsHeight, floor: floor) {
                DailyBarsChart(bars: bars, showsPaceLine: showsPaceLine, dayLabels: dayLabels, unit: unit)
            }
        }
    }

    /// The cycle's daily spend against its limit; nil without a daily series.
    private func cycleBars(_ spend: SpendPeriod, now: Date) -> [DayBar]? {
        guard provider.descriptor.capabilities.hasDailyChart, !spend.daily.isEmpty else {
            return nil
        }

        return PopoverPresentation.spendBars(spend, limit: spend.limit, today: now)
    }

    /// The session reads as a bare time; every other window names its day.
    private func resetText(for window: LimitWindow, now: Date) -> String? {
        let isShort = window.id == provider.descriptor.shortWindowID
        return CountdownFormatter.resetText(resetsAt: window.resetsAt, now: now, style: isShort ? .session : .long)
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
                let floor = budget.map { budget in
                    ChartFloor(
                        fraction: NSDecimalNumber(decimal: spend.spent / budget).doubleValue,
                        tint: PacingTint.forPacing(pacing), tick: pacing?.tickFraction
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Spend to date")
                        Spacer()
                        Text(budget.map { "\(spent) / \(BudgetUnit.dollars.format($0))" } ?? spent)
                            .font(.callout.monospacedDigit())
                    }

                    if provider.descriptor.capabilities.hasDailyChart, !spend.daily.isEmpty {
                        ChartedBarBlock(chartHeight: Self.barsHeight, floor: floor) {
                            DailyBarsChart(
                                bars: PopoverPresentation.spendBars(spend, limit: budget, today: now),
                                showsPaceLine: budget != nil, dayLabels: false, unit: .dollars
                            )
                        }
                    } else if let floor {
                        UsageBar(fraction: floor.fraction, tint: floor.tint, height: 5, tick: floor.tick)
                    }
                }
                .accessibilityElement(children: .combine)

                if let pacing {
                    PacingView(pacing: pacing, unit: .dollars, periodEnd: spend.period.end)
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
                Task { await appModel.refresh(provider.id, manual: true) }
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

import Foundation

/// The status lines under a provider's name in its Settings page header:
/// one summary line, or one line per failing half.
struct ProviderStatus: Equatable {
    enum Tone: Equatable {
        case neutral, good, warning, bad
    }

    struct Line: Equatable {
        let text: String
        let tone: Tone
    }

    let lines: [Line]

    init(lines: [Line]) {
        self.lines = lines
    }

    init(text: String, tone: Tone) {
        self.init(lines: [Line(text: text, tone: tone)])
    }

    /// `statuses` are the enabled halves' states; an empty list means every
    /// half is switched off. `errors` are the enabled halves' error messages.
    static func make(
        configured: Bool,
        enabled: Bool = true,
        statuses: [HalfStatus],
        errors: [HalfErrorMessage] = [],
        planName: String?
    ) -> ProviderStatus {
        guard configured else {
            return ProviderStatus(text: "Not set up", tone: .neutral)
        }

        guard enabled else {
            return ProviderStatus(text: "Disabled", tone: .neutral)
        }

        guard !statuses.isEmpty else {
            return ProviderStatus(text: "Nothing switched on", tone: .neutral)
        }

        // Each failing half says what went wrong, so two failures never collapse into one.
        guard errors.isEmpty else {
            return ProviderStatus(lines: errors.map { error in
                Line(text: error.line, tone: error.severity == .critical ? .bad : .warning)
            })
        }

        if statuses.contains(.expired) {
            return ProviderStatus(text: "Credential expired", tone: .bad)
        }

        if statuses.contains(.error) {
            return ProviderStatus(text: "Unable to refresh", tone: .warning)
        }

        guard statuses.contains(.ready) else {
            return ProviderStatus(text: "Connecting…", tone: .neutral)
        }

        let plan = planName.map { " · \($0)" } ?? ""
        return ProviderStatus(text: "Connected" + plan, tone: .good)
    }

    /// The status of `provider`'s enabled halves; `item` is its menu bar item,
    /// whose error marks each get an explanation.
    @MainActor
    static func make(for provider: ProviderViewModel, item: MenuBarItem?) -> ProviderStatus {
        let halves = [provider.subscription, provider.api].compactMap { $0 }.filter(\.isEnabled)
        let errors = halves.compactMap { half in
            PopoverPresentation.halfError(
                half,
                descriptor: provider.descriptor,
                display: half.half == .subscription ? item?.subscription : item?.api
            )
        }

        return make(
            configured: provider.isConfigured,
            enabled: provider.isEnabled,
            statuses: halves.map(\.status),
            errors: errors,
            planName: halves.compactMap { $0.report?.planName }.first
        )
    }
}

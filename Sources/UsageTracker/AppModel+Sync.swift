import Foundation

extension AppModel: SyncApplying {
    func syncedSettings() -> [SyncedSetting] {
        providers.map { .provider($0.id, settings(for: $0.id)) }
            + [.appearance(globalAppearance), .alerts(alertSwitches)]
            + providers.map { .budget($0.id, budget(for: $0.id)) }
    }

    func applySynced(_ setting: SyncedSetting) {
        switch setting {
        case let .provider(id, settings):
            guard settings != self.settings(for: id) else {
                return
            }
            setSettings(settings, for: id)
        case let .appearance(appearance):
            guard appearance != globalAppearance else {
                return
            }
            setGlobalAppearance(appearance)
        case let .alerts(switches):
            if switches.enabled != alertsEnabled {
                setAlertsEnabled(switches.enabled)
            }
            for kind in AlertKind.allCases where switches.kinds.contains(kind.rawValue) != alertKinds.contains(kind) {
                setAlertKind(kind, enabled: switches.kinds.contains(kind.rawValue))
            }
        case let .budget(id, budget):
            guard budget != self.budget(for: id) else {
                return
            }
            setBudget(budget, for: id)
        }
    }

    func sharedState(for target: RefreshTarget) -> SharedHalfState? {
        provider(target.provider).half(target.half)?.sharedState
    }

    func adoptShared(_ state: SharedHalfState, for target: RefreshTarget) {
        adoptRefresh(state, for: target)
    }

    func historySamples(for provider: Provider) -> [String: [UsageSample]] {
        self.provider(provider).subscription?.sharedHistory ?? [:]
    }

    func mergeHistory(_ samples: [String: [UsageSample]], for provider: Provider) {
        self.provider(provider).subscription?.mergeHistory(samples)
    }

    func selectedOrganization(for provider: Provider) -> String? {
        let model = self.provider(provider)
        return [model.subscription, model.api].compactMap { $0?.selectedOrganizationID }.first
    }

    func adoptOrganization(_ id: String?, for provider: Provider) {
        let model = self.provider(provider)
        model.subscription?.adoptOrganization(id)
        model.api?.adoptOrganization(id)
    }

    /// The credentials now come from elsewhere: each half takes a scheduled
    /// turn, which in Everything usually adopts another Mac's answer.
    func syncedCredentialsChanged() {
        Task { await refreshAll(manual: false) }
    }
}

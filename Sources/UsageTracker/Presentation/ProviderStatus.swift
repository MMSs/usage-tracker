import Foundation

/// One line summarising a provider for its Settings page header.
struct ProviderStatus: Equatable {
    enum Tone: Equatable {
        case neutral, good, warning, bad
    }

    let text: String
    let tone: Tone

    static func make(configured: Bool, enabled: Bool = true, statuses: [HalfStatus], planName: String?) -> ProviderStatus {
        guard configured else {
            return ProviderStatus(text: "Not set up", tone: .neutral)
        }

        guard enabled else {
            return ProviderStatus(text: "Disabled", tone: .neutral)
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
}

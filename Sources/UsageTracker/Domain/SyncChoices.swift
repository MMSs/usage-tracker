import Foundation

/// What this Mac shares with the user's other Macs through iCloud: the
/// settings bundle, and usage and credentials provider by provider. Which
/// providers and halves are on always stays per Mac.
struct SyncChoices: Equatable, Sendable {
    /// Appearance, menu-bar visibility, refresh rates, alerts and budgets.
    var sharesSettings: Bool
    /// Each shared provider's credentials go through iCloud Keychain and its
    /// reports, history, fetch turns, session starts and organization choice
    /// through CloudKit, so the Macs take turns asking it.
    var sharedProviders: Set<Provider>

    init(sharesSettings: Bool = false, sharedProviders: Set<Provider> = []) {
        self.sharesSettings = sharesSettings
        self.sharedProviders = sharedProviders
    }

    static let nothing = SyncChoices()
    static let everything = SyncChoices(sharesSettings: true, sharedProviders: Set(Provider.allCases))

    var isOff: Bool { !sharesSettings && sharedProviders.isEmpty }
    var sharesAnyUsage: Bool { !sharedProviders.isEmpty }

    func sharesUsage(of provider: Provider) -> Bool {
        sharedProviders.contains(provider)
    }

    /// The single choice the app offered before providers were shared one by one.
    init?(legacyMode: String) {
        switch legacyMode {
        case "off": self = .nothing
        case "settingsOnly": self = SyncChoices(sharesSettings: true)
        case "everything": self = .everything
        default: return nil
        }
    }
}

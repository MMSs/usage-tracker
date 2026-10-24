import Foundation

/// What the caller wants Settings to show: a provider's page, with its first
/// credential help open when arriving from `Set up`; or General.
struct SettingsRequest: Equatable, Sendable {
    var provider: Provider?
    var opensHelp = false

    static let general = SettingsRequest(provider: nil, opensHelp: false)
}

enum SettingsPage: Hashable {
    case general
    case provider(Provider)

    /// The requested provider's page when it is listed, otherwise General.
    static func resolve(_ request: SettingsRequest, listed: [Provider]) -> SettingsPage {
        if let provider = request.provider, listed.contains(provider) {
            return .provider(provider)
        }

        return .general
    }
}

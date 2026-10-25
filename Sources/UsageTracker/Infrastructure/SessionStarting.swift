import Foundation

/// A report service that can open its provider's 5-hour session by sending
/// one tiny message.
@MainActor
protocol SessionStarting: AnyObject {
    func startSession(credentials: [String: String]) async throws
}

enum SessionStartState: Equatable, Sendable {
    case idle, starting, failed
}

/// The model that sends the session-starting message.
protocol SessionModelStoring: AnyObject {
    func model(for provider: Provider) -> String
}

/// Reads the model from defaults; the app never writes it, so a user who wants
/// another model sets the key by hand.
final class UserDefaultsSessionModelStore: SessionModelStoring {
    /// The cheapest known model for each provider that can start a session.
    static let defaultModels: [Provider: String] = [.anthropic: "claude-haiku-5-5", .openai: "gpt-6-luna"]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func model(for provider: Provider) -> String {
        let stored = defaults.string(forKey: "sessionStart.model.\(provider.rawValue)")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty {
            return stored
        }

        return Self.defaultModels[provider] ?? ""
    }
}

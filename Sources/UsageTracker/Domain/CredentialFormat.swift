/// What a credential field accepts before it is saved to Keychain.
enum CredentialFormat: Equatable, Sendable {
    case plain
    case codexAuthJSON

    /// Why `value` cannot be saved, or nil when it can.
    func problem(with value: String) -> String? {
        switch self {
        case .plain:
            nil
        case .codexAuthJSON:
            (try? CodexAuth(json: value)) == nil
                ? "Paste the whole auth.json file. It needs tokens.access_token and tokens.refresh_token."
                : nil
        }
    }

    /// The mask shown for a stored `value`, or nil when it is empty. A Codex
    /// bundle is masked by its refresh token, not the JSON text; one that no
    /// longer parses shows ellipses only.
    func mask(of value: String) -> CredentialMask? {
        guard let whole = CredentialMask(value: value) else {
            return nil
        }

        switch self {
        case .plain:
            return whole
        case .codexAuthJSON:
            guard let auth = try? CodexAuth(json: value) else {
                return .hidden
            }
            return CredentialMask(value: auth.refreshToken) ?? .hidden
        }
    }
}

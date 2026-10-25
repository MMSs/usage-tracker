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
}

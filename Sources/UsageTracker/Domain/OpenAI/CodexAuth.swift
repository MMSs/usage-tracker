import Foundation

/// The `/oauth/token` refresh response. Codex keeps the old value for any
/// token the response omits.
struct CodexTokenGrant: Decodable, Equatable, Sendable {
    let idToken: String?
    let accessToken: String?
    let refreshToken: String?

    private enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

/// The tokens read from a pasted Codex `auth.json`. The values are credentials:
/// never log them or put them in error text.
struct CodexAuth: Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let accountID: String?

    /// Throws `FetchError.unauthorized` when the text is not a JSON object
    /// carrying both tokens.
    init(json: String) throws {
        guard let root = Self.object(json),
              let tokens = root["tokens"] as? [String: Any],
              let accessToken = Self.nonBlank(tokens["access_token"]),
              let refreshToken = Self.nonBlank(tokens["refresh_token"])
        else {
            throw FetchError.unauthorized
        }

        self.accessToken = accessToken
        self.refreshToken = refreshToken
        accountID = Self.nonBlank(tokens["account_id"]) ?? Self.accountID(inJWT: accessToken)
    }

    /// `json` with the grant's tokens swapped in and `last_refresh` set to
    /// `date`; every other key, and any token the grant omits, is kept.
    static func renewedJSON(_ json: String, grant: CodexTokenGrant, at date: Date) throws -> String {
        guard var root = object(json) else {
            throw FetchError.unauthorized
        }

        var tokens = root["tokens"] as? [String: Any] ?? [:]

        for (key, value) in [
            ("access_token", grant.accessToken),
            ("refresh_token", grant.refreshToken),
            ("id_token", grant.idToken),
        ] {
            if let value {
                tokens[key] = value
            }
        }

        root["tokens"] = tokens
        root["last_refresh"] = date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))

        let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .withoutEscapingSlashes])

        guard let text = String(data: data, encoding: .utf8) else {
            throw FetchError.unauthorized
        }

        return text
    }

    /// `json` pretty-printed with every string masked except the plainly
    /// harmless ones, so a stored bundle can be shown without its secrets.
    /// Keys the app does not know are masked too.
    static func maskedJSON(_ json: String) -> String? {
        guard let root = object(json),
              let data = try? JSONSerialization.data(
                  withJSONObject: masked(root, key: nil),
                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              )
        else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private static let plainKeys: Set = ["auth_mode", "last_refresh"]

    private static func masked(_ value: Any, key: String?) -> Any {
        switch value {
        case let object as [String: Any]:
            Dictionary(uniqueKeysWithValues: object.map { ($0.key, masked($0.value, key: $0.key)) })
        case let array as [Any]:
            array.map { masked($0, key: key) }
        case let text as String:
            key.map(plainKeys.contains) == true ? text : CredentialMask(value: text)?.text(ellipsisCount: 3) ?? text
        default:
            value
        }
    }

    private static func object(_ json: String) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    }

    private static func nonBlank(_ value: Any?) -> String? {
        guard let text = value as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return text
    }

    private static func accountID(inJWT jwt: String) -> String? {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)

        guard parts.count >= 2 else {
            return nil
        }

        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)

        guard let data = Data(base64Encoded: base64),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = claims["https://api.openai.com/auth"] as? [String: Any]
        else {
            return nil
        }

        return nonBlank(auth["chatgpt_account_id"])
    }
}

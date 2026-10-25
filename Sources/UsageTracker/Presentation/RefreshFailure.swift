import Foundation

/// Why a half's last refresh failed. Holds no credential, URL, or response
/// body, so it is safe to show and to log.
enum RefreshFailure: Equatable, Sendable {
    /// No response: offline, DNS, TLS, or a timeout.
    case transport
    /// An HTML 403 from bot protection.
    case challenge
    case unauthorized
    case httpStatus(Int)
    /// HTTP 429; scheduled refreshes wait until `until` when the service said when.
    case rateLimited(until: Date?)
    /// A response the app could not read: a changed shape or a non-HTTP reply.
    case decoding
    /// The credential could not be read from Keychain.
    case keychain
    /// The credential sees several organizations and the user has not chosen one.
    case needsOrganization
    /// Any other error.
    case unexpected

    init(_ error: any Error) {
        switch error as? FetchError {
        case .transport: self = .transport
        case .challenge: self = .challenge
        case .unauthorized: self = .unauthorized
        case let .httpStatus(code): self = .httpStatus(code)
        case let .rateLimited(until): self = .rateLimited(until: until)
        case .decoding, .invalidResponse: self = .decoding
        case .needsOrganizationChoice: self = .needsOrganization
        case nil: self = error is KeychainCredentialStoreError ? .keychain : .unexpected
        }
    }
}

extension RefreshFailure: CustomStringConvertible {
    var description: String {
        switch self {
        case .transport: "transport"
        case .challenge: "challenge"
        case .unauthorized: "unauthorized"
        case let .httpStatus(code): "http \(code)"
        case .rateLimited: "rate limited"
        case .decoding: "decoding"
        case .keychain: "keychain"
        case .needsOrganization: "needs organization"
        case .unexpected: "unexpected"
        }
    }
}

extension RefreshFailure {
    /// False when there was no response: the connection is down, which is not
    /// the provider's failure, so it neither alerts nor ends a streak.
    var alertsAsFailure: Bool {
        self != .transport
    }

    /// The cause in a failure alert: a fixed phrase, never a header, body or URL.
    var alertCause: String {
        switch self {
        case .challenge: "blocked by the provider's bot check"
        case .unauthorized: "credential expired"
        case let .httpStatus(code): "server error \(code)"
        case .rateLimited: "rate limited"
        case .decoding: "unexpected response"
        case .keychain: "couldn't read Keychain"
        case .needsOrganization: "choose an organization in Settings"
        case .unexpected: "unexpected error"
        case .transport: "network unavailable"
        }
    }
}

/// A half's last failure and when it happened; cleared by the next success.
struct RecordedFailure: Equatable, Sendable {
    let cause: RefreshFailure
    let date: Date
}

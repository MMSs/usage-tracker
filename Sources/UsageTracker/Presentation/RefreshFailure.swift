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
        case nil: self = .unexpected
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
        case .unexpected: "unexpected"
        }
    }
}

/// A half's last failure and when it happened; cleared by the next success.
struct RecordedFailure: Equatable, Sendable {
    let cause: RefreshFailure
    let date: Date
}

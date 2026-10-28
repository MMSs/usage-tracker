import Foundation

/// What a refresh left one half with, as another Mac adopts it instead of
/// asking the provider itself. Holds no credential.
struct SharedHalfState: Codable, Equatable, Sendable {
    var report: ProviderReport?
    var fetchedAt: Date?
    var failure: RecordedFailure?
    var rateLimitedUntil: Date?
    var retriesBlocked: Bool

    /// The later of the success and the failure it carries.
    var updatedAt: Date? {
        [fetchedAt, failure?.date].compactMap { $0 }.max()
    }

    /// A failure that says something about this Mac rather than the
    /// provider (no connection, an unreadable Keychain) stays here.
    var isShareable: Bool {
        switch failure?.cause {
        case .offline, .keychain: false
        default: updatedAt != nil
        }
    }
}

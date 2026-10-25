import Foundation
@testable import UsageTracker

/// A report fetcher that can also start a session; each start takes the next
/// scripted result (success when the script is empty).
@MainActor
final class StubSessionFetcher: ReportFetching, SessionStarting {
    var fetchResult: Result<ProviderReport, FetchError>
    /// One outcome per start call, consumed in order.
    var startResults: [Result<Void, any Error>] = []
    /// Held mid-start until resumed, when set.
    var startGate: SuspendedGate?
    private(set) var fetchCount = 0
    private(set) var startCount = 0
    private(set) var startCredentials: [[String: String]] = []

    init(fetchResult: Result<ProviderReport, FetchError>) {
        self.fetchResult = fetchResult
    }

    func fetchReport(credentials: [String: String], today: Date) async throws -> ProviderReport {
        fetchCount += 1
        return try fetchResult.get()
    }

    func startSession(credentials: [String: String]) async throws {
        startCount += 1
        startCredentials.append(credentials)
        if let startGate {
            await startGate.wait()
        }

        if !startResults.isEmpty {
            try startResults.removeFirst().get()
        }
    }
}

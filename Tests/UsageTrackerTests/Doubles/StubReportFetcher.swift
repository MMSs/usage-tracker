import Foundation
@testable import UsageTracker

/// Holds a fetch mid-flight until `resume()`.
@MainActor
final class SuspendedGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
final class StubReportFetcher: ReportFetching {
    var result: Result<ProviderReport, FetchError>
    var gate: SuspendedGate?
    private(set) var callCount = 0
    private(set) var lastCredentials: [String: String]?

    init(result: Result<ProviderReport, FetchError>) {
        self.result = result
    }

    func fetchReport(credentials: [String: String], today: Date) async throws -> ProviderReport {
        callCount += 1
        lastCredentials = credentials

        if let gate {
            await gate.wait()
        }

        return try result.get()
    }
}

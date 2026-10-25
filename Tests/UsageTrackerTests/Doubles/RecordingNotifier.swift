import Foundation
@testable import UsageTracker

@MainActor
final class RecordingNotifier: UsageNotifying {
    private(set) var delivered: [UsageAlert] = []

    private(set) var authorizationRequests = 0

    func requestAuthorization() {
        authorizationRequests += 1
    }

    func deliver(_ alert: UsageAlert) {
        delivered.append(alert)
    }
}

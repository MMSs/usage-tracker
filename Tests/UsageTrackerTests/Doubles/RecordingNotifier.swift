import Foundation
@testable import UsageTracker

@MainActor
final class RecordingNotifier: UsageNotifying {
    private(set) var delivered: [UsageAlert] = []

    func deliver(_ alert: UsageAlert) {
        delivered.append(alert)
    }
}

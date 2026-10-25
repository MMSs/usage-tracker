import Foundation
@testable import UsageTracker

/// Answers every provider with one fixed model, so tests never name a real one.
final class StubSessionModelStore: SessionModelStoring {
    private let fixed: String

    init(model: String = "test-model") {
        fixed = model
    }

    func model(for provider: Provider) -> String {
        fixed
    }
}

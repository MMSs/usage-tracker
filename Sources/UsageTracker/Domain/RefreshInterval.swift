import Foundation

/// The graded steps of the refresh slider, shortest first.
enum RefreshInterval: String, CaseIterable, Identifiable, Sendable {
    case thirtySeconds
    case oneMinute
    case twoMinutes
    case fiveMinutes
    case tenMinutes
    case fifteenMinutes
    case twentyMinutes
    case thirtyMinutes
    case oneHour

    static let `default` = RefreshInterval.fiveMinutes

    var id: String {
        rawValue
    }

    var seconds: Int {
        switch self {
        case .thirtySeconds: 30
        case .oneMinute: 60
        case .twoMinutes: 120
        case .fiveMinutes: 300
        case .tenMinutes: 600
        case .fifteenMinutes: 900
        case .twentyMinutes: 1200
        case .thirtyMinutes: 1800
        case .oneHour: 3600
        }
    }

    var duration: Duration {
        .seconds(seconds)
    }

    var title: String {
        switch self {
        case .thirtySeconds: "30 s"
        case .oneHour: "1 hour"
        default: "\(seconds / 60) min"
        }
    }

    /// Position on the slider.
    var step: Int {
        Self.allCases.firstIndex(of: self)!
    }

    /// The step nearest to a slider value.
    static func at(step: Double) -> RefreshInterval {
        let index = Int(step.rounded()).clamped(to: 0 ... allCases.count - 1)
        return allCases[index]
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

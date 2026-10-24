import Foundation

enum RefreshInterval: String, CaseIterable, Identifiable, Sendable {
    case oneMinute
    case fiveMinutes
    case fifteenMinutes
    case oneHour

    static let `default` = RefreshInterval.fiveMinutes

    var id: String {
        rawValue
    }

    var duration: Duration {
        switch self {
        case .oneMinute:
            return .seconds(60)
        case .fiveMinutes:
            return .seconds(300)
        case .fifteenMinutes:
            return .seconds(900)
        case .oneHour:
            return .seconds(3600)
        }
    }

    var title: String {
        switch self {
        case .oneMinute:
            return "1 min"
        case .fiveMinutes:
            return "5 min"
        case .fifteenMinutes:
            return "15 min"
        case .oneHour:
            return "1 hour"
        }
    }
}

import Foundation

enum BudgetUnit: String, Codable, Equatable, Sendable {
    case dollars
    case percent

    /// Dollars keep cents; percentages keep one decimal below 10, where
    /// daily shares live. Output is pinned to en_US with half-up rounding so
    /// figures read the same on every Mac.
    func format(_ amount: Decimal) -> String {
        switch self {
        case .dollars:
            "$\(amount.formatted(Self.style(fractionDigits: 2...2)))"
        case .percent:
            "\(amount.formatted(Self.style(fractionDigits: abs(amount) < 10 ? 0...1 : 0...0)))%"
        }
    }

    private static func style(fractionDigits: ClosedRange<Int>) -> Decimal.FormatStyle {
        .number
            .locale(Locale(identifier: "en_US"))
            .rounded(rule: .toNearestOrAwayFromZero)
            .precision(.fractionLength(fractionDigits))
    }
}

/// Local-midnight dates; `end` is exclusive.
struct CyclePeriod: Codable, Equatable, Sendable {
    let start: Date
    let end: Date
}

struct DaySpend: Codable, Equatable, Identifiable, Sendable {
    let day: Date
    let amount: Decimal

    var id: Date { day }
}

struct SpendPeriod: Codable, Equatable, Sendable {
    let period: CyclePeriod
    let spent: Decimal
    /// nil: unlimited or no limit known.
    let limit: Decimal?
    let unit: BudgetUnit
    let daily: [DaySpend]

    /// The amount recorded for `day`, or 0 when the series has no entry.
    func spent(on day: Date, calendar: Calendar = .current) -> Decimal {
        daily.first { calendar.isDate($0.day, inSameDayAs: day) }?.amount ?? 0
    }
}

struct LimitWindow: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let label: String
    let percentUsed: Double
    let resetsAt: Date?
    let parentID: String?

    var isOpen: Bool { resetsAt != nil }
}

struct MoneyRow: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let label: String
    let amount: Decimal
    let limit: Decimal?
}

struct ProviderReport: Codable, Equatable, Sendable {
    var planName: String?
    var windows: [LimitWindow]
    var extras: [MoneyRow]
    /// Cursor cycle (subscription half) or API month (api half).
    var spend: SpendPeriod?

    func children(of id: String) -> [LimitWindow] {
        windows.filter { $0.parentID == id }
    }

    var topLevelWindows: [LimitWindow] {
        windows.filter { $0.parentID == nil }
    }
}

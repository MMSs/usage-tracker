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
    /// How long the window lasts, when known (e.g. 5 hours); nil for cached
    /// reports and providers that do not say.
    let windowLength: TimeInterval?

    init(
        id: String,
        label: String,
        percentUsed: Double,
        resetsAt: Date?,
        parentID: String?,
        windowLength: TimeInterval? = nil
    ) {
        self.id = id
        self.label = label
        self.percentUsed = percentUsed
        self.resetsAt = resetsAt
        self.parentID = parentID
        self.windowLength = windowLength
    }

    var isOpen: Bool { resetsAt != nil }

    /// `resetsAt` while the window is running at `now`; nil once it has passed,
    /// and nil when it lies a whole window length away, which is how a
    /// provider reports a window nobody has started (the reset slides forward
    /// on every fetch). The slack absorbs request latency and clock drift, so
    /// a session started under a minute ago reads as closed until the next fetch.
    static func runningReset(_ resetsAt: Date?, windowLength: TimeInterval, now: Date) -> Date? {
        guard let resetsAt, resetsAt > now else {
            return nil
        }

        return abs(resetsAt.timeIntervalSince(now) - windowLength) <= unstartedSlack ? nil : resetsAt
    }

    private static let unstartedSlack: TimeInterval = 60

    /// The whole percent with its sign, e.g. "53%". The value is clamped
    /// first so a bad number can never overflow the integer conversion.
    var percentText: String {
        let clamped = percentUsed.isFinite ? min(max(percentUsed, 0), 999_999) : 0

        return "\(Int(clamped.rounded()))%"
    }
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

    /// The money row carrying a window's amounts (Cursor team plans), if any.
    func extra(for windowID: String) -> MoneyRow? {
        extras.first { $0.id == windowID }
    }

    /// Money rows that match no window and so are shown on their own.
    var standaloneExtras: [MoneyRow] {
        extras.filter { extra in !windows.contains { $0.id == extra.id } }
    }
}

import Foundation
import SwiftUI

enum PacingStatus: Equatable, Sendable {
    case onTrack(by: Decimal)
    case over(by: Decimal)
}

struct Pacing: Equatable, Sendable {
    let totalDays: Int, elapsedDays: Int, remainingDays: Int
    /// Spend so far in the period, today included; what `status` and the tint compare.
    let spent: Decimal
    /// budget × (elapsedDays + 1) / totalDays: where spend may reach by the end of today.
    let idealSpend: Decimal
    let status: PacingStatus
    /// max(budget − spentBeforeToday, 0) / remainingDays
    let todayBudget: Decimal
    /// todayBudget − spentToday
    let leftForToday: Decimal
    /// nil until at least one full day has elapsed.
    let projectedSpend: Decimal?
    /// idealSpend / budget, clamped to 0…1.
    let tickFraction: Double
    /// spent / budget, clamped to 0…1.
    let fillFraction: Double
}

enum PacingCalculator {
    /// nil when budget ≤ 0, the period is empty, or today is outside the period.
    static func make(
        spent: Decimal,
        spentToday: Decimal,
        budget: Decimal,
        period: CyclePeriod,
        today: Date,
        calendar: Calendar = .current
    ) -> Pacing? {
        let startDay = calendar.startOfDay(for: period.start)
        let endDay = calendar.startOfDay(for: period.end)
        let todayDay = calendar.startOfDay(for: today)
        let totalDays = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0

        guard budget > 0, totalDays > 0, todayDay >= startDay, todayDay < endDay else {
            return nil
        }

        // Full days before today; today's own spend is still in progress.
        let elapsedDays = calendar.dateComponents([.day], from: startDay, to: todayDay).day ?? 0
        let remainingDays = totalDays - elapsedDays

        // `spent` already includes today, so today counts as elapsed: an
        // exactly on-pace spender stays on track all day.
        let idealSpend = budget * Decimal(elapsedDays + 1) / Decimal(totalDays)
        let difference = idealSpend - spent
        let status: PacingStatus = difference >= 0
            ? .onTrack(by: difference)
            : .over(by: -difference)

        let spentBeforeToday = max(spent - spentToday, 0)
        let todayBudget = max(budget - spentBeforeToday, 0) / Decimal(remainingDays)
        let leftForToday = todayBudget - spentToday
        let projectedSpend = elapsedDays > 0
            ? spentBeforeToday / Decimal(elapsedDays) * Decimal(totalDays)
            : nil

        return Pacing(
            totalDays: totalDays,
            elapsedDays: elapsedDays,
            remainingDays: remainingDays,
            spent: spent,
            idealSpend: idealSpend,
            status: status,
            todayBudget: todayBudget,
            leftForToday: leftForToday,
            projectedSpend: projectedSpend,
            tickFraction: clampedFraction(idealSpend, of: budget),
            fillFraction: clampedFraction(spent, of: budget)
        )
    }

    /// Paces against `budgetOverride` when given, otherwise against the spend's limit.
    static func make(
        _ spend: SpendPeriod,
        budgetOverride: Decimal? = nil,
        today: Date,
        calendar: Calendar = .current
    ) -> Pacing? {
        guard let budget = budgetOverride ?? spend.limit else {
            return nil
        }

        return make(
            spent: spend.spent,
            spentToday: spend.spent(on: today, calendar: calendar),
            budget: budget,
            period: spend.period,
            today: today,
            calendar: calendar
        )
    }

    private static func clampedFraction(_ part: Decimal, of whole: Decimal) -> Double {
        let value = NSDecimalNumber(decimal: part / whole).doubleValue
        return min(max(value, 0), 1)
    }
}

/// Pacing expressed as colour. Driven by spend relative to ideal spend rather
/// than raw consumption, because spending most of the budget is expected at
/// the end of a period and alarming at the start.
enum PacingTint: Equatable, Sendable {
    case onPace
    case nearingLimit
    case overBudget
    case neutral

    /// Spend may run this far past ideal before the tint escalates from amber
    /// to red.
    private static let overBudgetRatio = Decimal(string: "1.15")!

    static func forPacing(_ pacing: Pacing?) -> PacingTint {
        guard let pacing else {
            return .neutral
        }

        let actual = pacing.spent

        guard pacing.idealSpend > 0 else {
            return actual > 0 ? .nearingLimit : .onPace
        }

        let ratio = actual / pacing.idealSpend

        if ratio <= 1 {
            return .onPace
        }

        return ratio <= overBudgetRatio ? .nearingLimit : .overBudget
    }

    /// Tint for spend against a budget, e.g. today's spend against today's budget.
    static func forSpend(_ spend: Decimal, budget: Decimal) -> PacingTint {
        guard budget > 0 else {
            return spend > 0 ? .overBudget : .onPace
        }

        let ratio = spend / budget

        if ratio <= 1 {
            return .onPace
        }

        return ratio <= overBudgetRatio ? .nearingLimit : .overBudget
    }

    /// Tint for the share of the budget already used, as a percentage.
    static func forRemaining(percentUsed: Double) -> PacingTint {
        switch percentUsed {
        case ..<50:
            return .onPace
        case ..<80:
            return .nearingLimit
        default:
            return .overBudget
        }
    }

    var color: Color {
        switch self {
        case .onPace:
            return .green
        case .nearingLimit:
            return .orange
        case .overBudget:
            return .red
        case .neutral:
            return .secondary
        }
    }
}

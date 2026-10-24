import SwiftUI

struct PacingView: View {
    let pacing: Pacing
    let unit: BudgetUnit
    let periodEnd: Date

    private var tint: PacingTint { PacingTint.forPacing(pacing) }

    private var projectedText: String {
        guard let projected = pacing.projectedSpend else {
            return "—"
        }

        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: periodEnd) ?? periodEnd
        return "\(unit.format(projected)) by \(PopoverPresentation.dayMonth(lastDay))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(
                    PopoverPresentation.pillText(pacing, unit: unit),
                    systemImage: tint == .overBudget ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(tint.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(tint.color.opacity(0.14), in: Capsule())

                Spacer()

                Text(PopoverPresentation.daysLeftText(pacing))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                tile("Daily budget", unit.format(pacing.todayBudget))
                tile("Left for today", unit.format(pacing.leftForToday))
                tile("Projected", projectedText)
            }
        }
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.callout.monospacedDigit())
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

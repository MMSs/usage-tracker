import SwiftUI

struct PacingView: View {
    let pacing: Pacing
    let unit: BudgetUnit
    let periodEnd: Date

    private var tint: PacingTint { PacingTint.forPacing(pacing) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(
                    PopoverPresentation.pillText(pacing, unit: unit),
                    systemImage: PopoverPresentation.pillSymbol(tint)
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

            HStack(alignment: .top, spacing: 6) {
                tile("Daily budget", unit.format(pacing.todayBudget), caption: nil)
                tile("Left for today", unit.format(pacing.leftForToday), caption: nil)
                tile(
                    "Projected", PopoverPresentation.projectedValue(pacing, unit: unit),
                    caption: PopoverPresentation.projectedCaption(pacing, periodEnd: periodEnd)
                )
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Every tile reserves the caption line so the three stay the same height.
    private func tile(_ title: String, _ value: String, caption: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.callout.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(caption ?? "\u{00A0}")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

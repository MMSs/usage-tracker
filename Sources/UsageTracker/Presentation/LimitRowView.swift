import SwiftUI

/// A rounded progress bar with an optional pacing tick.
struct UsageBar: View {
    let fraction: Double
    let tint: PacingTint
    let height: CGFloat
    let tick: Double?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.14))
                Capsule()
                    .fill(tint.color)
                    .frame(width: width * min(max(fraction, 0), 1))
                if let tick {
                    Capsule()
                        .fill(.primary)
                        .frame(width: 1.5, height: height + 4)
                        .offset(x: min(max(width * tick - 0.75, 0), width - 1.5))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: height + (tick == nil ? 0 : 4))
        .accessibilityHidden(true)
    }
}

struct LimitRowView: View {
    let label: String
    /// From `PopoverPresentation.rowText`.
    let text: String
    /// nil draws no bar.
    let fraction: Double?
    let indented: Bool
    let tick: Double?
    let tint: PacingTint

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LimitRowLine(label: label, text: text, indented: indented)

            if let fraction {
                UsageBar(fraction: fraction, tint: tint, height: indented ? 3 : 5, tick: tick)
            }
        }
        .padding(.leading, indented ? 12 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(text)
    }
}

/// A window row's label and text, above its bar or its chart.
struct LimitRowLine: View {
    let label: String
    let text: String
    let indented: Bool

    var body: some View {
        HStack {
            Text(label)
                .font(indented ? .caption : .body)
            Spacer()
            Text(text)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

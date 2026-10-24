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
    let window: LimitWindow
    let resetText: String?
    let indented: Bool
    let tick: Double?
    let tint: PacingTint

    private var percentText: String {
        "\(Int(window.percentUsed.rounded()))%" + (resetText.map { " · " + $0 } ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(window.label)
                    .font(indented ? .caption : .body)
                Spacer()
                Text(percentText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            UsageBar(fraction: window.percentUsed / 100, tint: tint, height: indented ? 3 : 5, tick: tick)
        }
        .padding(.leading, indented ? 12 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(window.label)
        .accessibilityValue(percentText)
    }
}

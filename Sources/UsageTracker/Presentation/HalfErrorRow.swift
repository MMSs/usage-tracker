import SwiftUI

/// A tinted row at the top of a popover section saying which half failed,
/// why, and how to fix it.
struct HalfErrorRow: View {
    let message: HalfErrorMessage
    /// "Last success 14:31" when a cached report is still on screen.
    let lastSuccess: String?

    private var tint: Color {
        switch message.severity {
        case .warning: .orange
        case .critical: .red
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(message.text)
                    .font(.callout.weight(.medium))

                if let fix = message.fix {
                    Text(fix)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let lastSuccess {
                    Text(lastSuccess)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.12))
        )
        .accessibilityElement(children: .combine)
    }
}

#Preview("Error rows") {
    VStack(spacing: 12) {
        HalfErrorRow(
            message: HalfErrorMessage(
                text: "API spend: Couldn't reach api.anthropic.com.",
                fix: "Check your connection; it retries automatically.",
                severity: .warning
            ),
            lastSuccess: "Last success 14:31"
        )
        HalfErrorRow(
            message: HalfErrorMessage(
                text: "Plan usage: Credential expired — replace it in Settings", fix: nil, severity: .critical
            ),
            lastSuccess: nil
        )
    }
    .padding()
    .frame(width: 340)
}

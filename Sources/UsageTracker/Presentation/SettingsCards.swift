import SwiftUI

/// A strip styled like the menu bar, showing the item at its real size next
/// to a sample clock so appearance changes can be judged in context.
struct MenuBarPreviewStrip: View {
    let item: MenuBarItem?
    let appearance: MenuBarAppearance
    let displayName: String
    var caption = "How the item looks in the menu bar."
    var placeholder = "No data yet"

    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    private var barFill: LinearGradient {
        isDark
            ? LinearGradient(colors: [Color(white: 0.22), Color(white: 0.14)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(white: 0.97), Color(white: 0.91)], startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                Spacer(minLength: 0)

                if let item {
                    MenuBarLabel(item: item, appearance: appearance, displayName: displayName)
                } else {
                    Text(placeholder)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Text("Tue 09:41")
                    .font(.system(size: 13))
                    .foregroundStyle(isDark ? Color.white.opacity(0.9) : Color.black.opacity(0.85))
            }
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(barFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isDark ? 0.12 : 0.1), lineWidth: 1)
            )

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Provider glyph, name, and a one-line status with a coloured dot.
struct ProviderStatusHeader: View {
    let provider: Provider
    let displayName: String
    let status: ProviderStatus
    let updatedText: String?
    /// Nil hides the switch (previews, unconfigured providers).
    var isEnabled: Binding<Bool>? = nil

    private var dotColor: Color {
        switch status.tone {
        case .neutral: .secondary
        case .good: .green
        case .warning: .orange
        case .bad: .red
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            ProviderGlyph(provider: provider)
                .fill(.primary)
                .frame(width: 26, height: 26)
                .padding(11)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(.title3.weight(.semibold))

                HStack(spacing: 6) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 7, height: 7)
                    Text(status.text)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 6) {
                if let isEnabled {
                    Toggle("Enabled", isOn: isEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .help("Show this provider in the menu bar and keep it refreshing")
                }

                if let updatedText {
                    Text(updatedText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

#Preview("Preview strip") {
    MenuBarPreviewStrip(
        item: MenuBarItem(
            provider: .cursor,
            subscription: .meters([
                MenuBarMeter(letter: "D", text: "12/48", countdown: nil, fraction: 0.25, tick: nil, tint: .onPace),
                MenuBarMeter(letter: "C", text: "41%", countdown: nil, fraction: 0.41, tick: 0.5, tint: .onPace),
            ], stale: false, errorMark: false),
            api: nil
        ),
        appearance: .default,
        displayName: "Cursor"
    )
    .padding()
    .frame(width: 440)
}

#Preview("Status header") {
    VStack(spacing: 16) {
        ProviderStatusHeader(provider: .cursor, displayName: "Cursor", status: ProviderStatus(text: "Connected · Pro", tone: .good), updatedText: "Updated 14:31", isEnabled: .constant(true))
        ProviderStatusHeader(provider: .anthropic, displayName: "Anthropic", status: ProviderStatus(text: "Not set up", tone: .neutral), updatedText: nil)
    }
    .padding()
    .frame(width: 440)
}

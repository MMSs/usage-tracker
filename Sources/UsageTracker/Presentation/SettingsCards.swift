import SwiftUI

/// A strip styled like the menu bar, showing items at their real size next
/// to a sample clock so appearance changes can be judged in context. Items
/// too wide for the strip shrink together, keeping their proportions.
struct MenuBarPreviewStrip: View {
    struct Entry: Identifiable {
        let item: MenuBarItem
        let appearance: MenuBarAppearance
        let displayName: String

        var id: Provider { item.provider }
    }

    let entries: [Entry]
    let caption: String
    let placeholder: String

    @Environment(\.colorScheme) private var colorScheme

    init(entries: [Entry], caption: String = "How the item looks in the menu bar.", placeholder: String = "No data yet") {
        self.entries = entries
        self.caption = caption
        self.placeholder = placeholder
    }

    /// One provider's item, or the placeholder when it has none.
    init(
        item: MenuBarItem?,
        appearance: MenuBarAppearance,
        displayName: String,
        caption: String = "How the item looks in the menu bar.",
        placeholder: String = "No data yet"
    ) {
        self.init(
            entries: item.map { [Entry(item: $0, appearance: appearance, displayName: displayName)] } ?? [],
            caption: caption,
            placeholder: placeholder
        )
    }

    nonisolated static let itemSpacing: CGFloat = 12

    /// The factor that fits items of `widths`, `spacing` apart, into `available`; never above 1.
    nonisolated static func scale(widths: [CGFloat], spacing: CGFloat, available: CGFloat) -> CGFloat {
        let natural = widths.reduce(0, +) + spacing * CGFloat(max(widths.count - 1, 0))
        guard natural > available, natural > 0 else {
            return 1
        }

        return max(available, 0) / natural
    }

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

                if entries.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                } else {
                    UniformScaleRow(spacing: Self.itemSpacing) {
                        ForEach(entries) { entry in
                            itemView(entry)
                        }
                    }
                    // Takes all the width the clock leaves before the spacer gets any.
                    .layoutPriority(1)
                }

                Text("Tue 09:41")
                    .font(.system(size: 13))
                    .foregroundStyle(isDark ? Color.white.opacity(0.9) : Color.black.opacity(0.85))
                    .fixedSize()
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

    /// The item drawn as `MenuBarLabel` draws it, but resizable so the row can shrink it.
    @ViewBuilder
    private func itemView(_ entry: Entry) -> some View {
        if let image = MenuBarItemImage.render(
            entry.item,
            appearance: entry.appearance,
            displayName: entry.displayName,
            darkMenuBar: isDark
        ) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .accessibilityLabel(entry.item.accessibilityText(displayName: entry.displayName))
        } else {
            Text(entry.item.accessibilityText(displayName: entry.displayName))
                .font(.system(size: 13))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }
}

/// Lays its views out in a row at their natural size and, when the row is
/// wider than offered, shrinks every view and gap by the same factor.
private struct UniformScaleRow: Layout {
    let spacing: CGFloat

    private func layout(_ subviews: Subviews, width: CGFloat?) -> (sizes: [CGSize], scale: CGFloat) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let scale = width.map {
            MenuBarPreviewStrip.scale(widths: sizes.map(\.width), spacing: spacing, available: $0)
        } ?? 1
        return (sizes, scale)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (sizes, scale) = layout(subviews, width: proposal.width)
        let width = sizes.map(\.width).reduce(0, +) + spacing * CGFloat(max(sizes.count - 1, 0))
        return CGSize(width: width * scale, height: (sizes.map(\.height).max() ?? 0) * scale)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (sizes, scale) = layout(subviews, width: bounds.width)
        var x = bounds.minX
        for (subview, size) in zip(subviews, sizes) {
            let scaled = CGSize(width: size.width * scale, height: size.height * scale)
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(scaled))
            x += scaled.width + spacing * scale
        }
    }
}

/// Provider glyph, name, and status lines with coloured dots.
struct ProviderStatusHeader: View {
    let provider: Provider
    let displayName: String
    let status: ProviderStatus
    let updatedText: String?
    /// Nil hides the switch (previews, unconfigured providers).
    var isEnabled: Binding<Bool>? = nil

    private func dotColor(_ tone: ProviderStatus.Tone) -> Color {
        switch tone {
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

                ForEach(Array(status.lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Circle()
                            .fill(dotColor(line.tone))
                            .frame(width: 7, height: 7)
                            // Centres the dot on the first line of wrapped text.
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        Text(line.text)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.callout)
                }
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
        ProviderStatusHeader(
            provider: .anthropic,
            displayName: "Anthropic",
            status: ProviderStatus(lines: [
                .init(text: "Plan usage: claude.ai asked for a browser check. Open claude.ai in your browser, then Refresh.", tone: .warning),
                .init(text: "API spend: Anthropic API is rate limiting requests; retrying at 14:35.", tone: .warning),
            ]),
            updatedText: "Updated 14:31",
            isEnabled: .constant(true)
        )
    }
    .padding()
    .frame(width: 440)
}

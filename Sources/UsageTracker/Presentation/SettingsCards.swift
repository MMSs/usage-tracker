import SwiftUI

/// A strip styled like the menu bar, showing items at their real size next
/// to a sample clock so appearance changes can be judged in context. Items
/// too wide for the strip shrink together, keeping their proportions, down to
/// `minimumScale`; past that the leftmost items are left out, as the menu bar
/// itself drops items that run out of room.
struct MenuBarPreviewStrip: View {
    struct Entry: Identifiable {
        let item: MenuBarItem
        let appearance: MenuBarAppearance
        let halves: MenuBarHalves
        let displayName: String

        var id: Provider { item.provider }
    }

    let entries: [Entry]
    let caption: String
    let placeholder: String

    @Environment(\.colorScheme) private var colorScheme
    /// The width offered to the items, for telling VoiceOver which are left out.
    @State private var rowWidth: CGFloat?

    init(entries: [Entry], caption: String = "How the item looks in the menu bar.", placeholder: String = "No data yet") {
        self.entries = entries
        self.caption = caption
        self.placeholder = placeholder
    }

    /// One provider's item, or the placeholder when it has none.
    init(
        item: MenuBarItem?,
        appearance: MenuBarAppearance,
        halves: MenuBarHalves = .all,
        displayName: String,
        caption: String = "How the item looks in the menu bar.",
        placeholder: String = "No data yet"
    ) {
        self.init(
            entries: item.map { [Entry(item: $0, appearance: appearance, halves: halves, displayName: displayName)] } ?? [],
            caption: caption,
            placeholder: placeholder
        )
    }

    nonisolated static let itemSpacing: CGFloat = 12
    /// Smaller than this the items are too small to judge.
    nonisolated static let minimumScale: CGFloat = 0.7
    /// Rounding slack: a row shrunk to exactly fit can come out a hair over.
    nonisolated static let fitTolerance: CGFloat = 0.5

    /// How a row of items is fitted: one factor for every item and gap, and how many are left out from the left.
    struct Fit: Equatable {
        let scale: CGFloat
        let hidden: Int
    }

    /// The row's natural width: the items `spacing` apart.
    nonisolated static func naturalWidth(_ widths: some Collection<CGFloat>, spacing: CGFloat) -> CGFloat {
        widths.reduce(0, +) + spacing * CGFloat(max(widths.count - 1, 0))
    }

    /// Fits items of `widths`, `spacing` apart, into `available`: shrinks them
    /// together, never above 1 nor below `minimumScale`, then leaves out
    /// items from the left until the rest fit.
    nonisolated static func fit(widths: [CGFloat], spacing: CGFloat, available: CGFloat) -> Fit {
        let natural = naturalWidth(widths, spacing: spacing)
        guard natural > available, natural > 0 else {
            return Fit(scale: 1, hidden: 0)
        }

        let scale = max(minimumScale, max(available, 0) / natural)
        var hidden = 0
        while hidden < widths.count,
              naturalWidth(widths.dropFirst(hidden), spacing: spacing) * scale > available + fitTolerance {
            hidden += 1
        }

        return Fit(scale: scale, hidden: hidden)
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
                if entries.isEmpty {
                    Spacer(minLength: 0)

                    Text(placeholder)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                } else {
                    items
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

    /// The items, right-aligned in all the width the clock leaves. The row
    /// places them; the same fit here hides the left-out ones from VoiceOver.
    private var items: some View {
        let images = entries.map { entry in
            MenuBarItemImage.render(entry.item, appearance: entry.appearance, halves: entry.halves, displayName: entry.displayName, darkMenuBar: isDark)
        }
        let widths = zip(entries, images).map { entry, image in
            image?.size.width ?? Self.fallbackWidth(entry)
        }
        let hidden = rowWidth.map { Self.fit(widths: widths, spacing: Self.itemSpacing, available: $0).hidden } ?? 0

        return UniformScaleRow(spacing: Self.itemSpacing) {
            ForEach(Array(zip(entries, images).enumerated()), id: \.element.0.id) { index, pair in
                itemView(pair.0, image: pair.1)
                    .accessibilityHidden(index < hidden)
            }
        }
        .clipped()
        .frame(maxWidth: .infinity, alignment: .trailing)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            rowWidth = width
        }
    }

    private static let fallbackFont = NSFont.systemFont(ofSize: 13)

    private static func fallbackWidth(_ entry: Entry) -> CGFloat {
        (entry.item.visible(in: entry.appearance, halves: entry.halves).accessibilityText(displayName: entry.displayName) as NSString)
            .size(withAttributes: [.font: fallbackFont]).width
    }

    /// The item drawn as `MenuBarLabel` draws it, but resizable so the row can shrink it.
    @ViewBuilder
    private func itemView(_ entry: Entry, image: NSImage?) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .accessibilityLabel(entry.item.visible(in: entry.appearance, halves: entry.halves).accessibilityText(displayName: entry.displayName))
        } else {
            Text(entry.item.visible(in: entry.appearance, halves: entry.halves).accessibilityText(displayName: entry.displayName))
                .font(.system(size: 13))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }
}

/// Lays its views out in a row at their natural size, fitted by
/// `MenuBarPreviewStrip.fit`: shrunk by one factor, and with the views that
/// still do not fit left out from the left.
private struct UniformScaleRow: Layout {
    let spacing: CGFloat

    private func layout(_ subviews: Subviews, width: CGFloat?) -> (sizes: [CGSize], fit: MenuBarPreviewStrip.Fit) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let fit = width.map {
            MenuBarPreviewStrip.fit(widths: sizes.map(\.width), spacing: spacing, available: $0)
        } ?? MenuBarPreviewStrip.Fit(scale: 1, hidden: 0)
        return (sizes, fit)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (sizes, fit) = layout(subviews, width: proposal.width)
        let shown = sizes.dropFirst(fit.hidden)
        let width = MenuBarPreviewStrip.naturalWidth(shown.map(\.width), spacing: spacing)
        return CGSize(width: width * fit.scale, height: (shown.map(\.height).max() ?? 0) * fit.scale)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (sizes, fit) = layout(subviews, width: bounds.width)
        var x = bounds.minX
        for (index, (subview, size)) in zip(subviews, sizes).enumerated() {
            guard index >= fit.hidden else {
                // Left out: no size, and outside the clipped row.
                subview.place(at: CGPoint(x: bounds.minX - 10_000, y: bounds.midY), proposal: .zero)
                continue
            }

            let scaled = CGSize(width: size.width * fit.scale, height: size.height * fit.scale)
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(scaled))
            x += scaled.width + spacing * fit.scale
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
                MenuBarMeter(letter: "D", text: "12/48", countdown: nil, fraction: 0.25, tick: nil, tint: .onPace, role: .short),
                MenuBarMeter(letter: "C", text: "41%", countdown: nil, fraction: 0.41, tick: 0.5, tint: .onPace, role: .long),
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

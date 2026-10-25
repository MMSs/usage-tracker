import AppKit
import SwiftUI

/// Renders the menu bar item into one image. The menu bar lays out a label's
/// parts itself, so glyph, text and graph are drawn together: a template when
/// nothing is coloured so the system tints it, otherwise in the menu bar's
/// own foreground colour.
enum MenuBarItemImage {
    static let height: CGFloat = 18

    @MainActor
    static func render(
        _ full: MenuBarItem,
        appearance: MenuBarAppearance,
        halves: MenuBarHalves = .all,
        displayName: String,
        darkMenuBar: Bool
    ) -> NSImage? {
        let item = full.visible(in: appearance, halves: halves)
        let colored = isColored(item, appearance: appearance)
        let palette = MenuBarPalette(
            foreground: colored && darkMenuBar ? .white : .black,
            colored: colored
        )
        let content = MenuBarItemContent(item: item, appearance: appearance, palette: palette)
            .frame(height: height)

        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2

        guard let image = renderer.nsImage else {
            return nil
        }

        image.isTemplate = !colored
        image.accessibilityDescription = item.accessibilityText(displayName: displayName)

        return image
    }

    static func isColored(_ item: MenuBarItem, appearance: MenuBarAppearance) -> Bool {
        guard appearance.colored else {
            return false
        }

        return [item.subscription, item.api].contains { half in
            switch half {
            case .meters, .money:
                true
            case let .status(status):
                status == .expired || status == .error
            case nil:
                false
            }
        }
    }
}

struct MenuBarPalette {
    let foreground: Color
    let colored: Bool

    var track: Color { foreground.opacity(0.25) }
    var tick: Color { foreground.opacity(0.9) }
    var error: Color { colored ? .red : foreground }

    func fill(_ tint: PacingTint) -> Color {
        colored && tint != .neutral ? tint.color : foreground.opacity(0.7)
    }

    func text(_ tint: PacingTint) -> Color {
        colored && tint != .neutral ? tint.color : foreground
    }
}

private struct MenuBarItemContent: View {
    let item: MenuBarItem
    let appearance: MenuBarAppearance
    let palette: MenuBarPalette

    var body: some View {
        HStack(spacing: 4) {
            ProviderGlyph(provider: item.provider)
                .fill(palette.foreground)
                .frame(width: 14, height: 14)

            if let subscription = item.subscription {
                HalfView(display: subscription, appearance: appearance, palette: palette)
            }

            if item.showsDivider {
                Rectangle()
                    .fill(palette.foreground.opacity(0.35))
                    .frame(width: 1, height: 12)
            }

            if let api = item.api {
                HalfView(display: api, appearance: appearance, palette: palette)
            }
        }
    }
}

private struct HalfView: View {
    let display: HalfDisplay
    let appearance: MenuBarAppearance
    let palette: MenuBarPalette

    var body: some View {
        switch display {
        case let .status(status):
            statusView(status)
        case let .meters(meters, stale, errorMark):
            HStack(spacing: 4) {
                if appearance.drawsText || appearance.drawsCountdown {
                    MenuBarText(
                        meters: meters,
                        showsValue: appearance.drawsText,
                        showsCountdown: appearance.drawsCountdown,
                        palette: palette
                    )
                }

                if appearance.drawsGraph {
                    graph(meters)
                }
            }
            .opacity(stale ? 0.6 : 1)
            .modifier(ErrorMark(shown: errorMark, color: palette.error))
        case let .money(text, meter, stale, errorMark):
            HStack(spacing: 4) {
                if appearance.showsSpendAmount(hasMeter: meter != nil) {
                    Text(text)
                        .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(palette.text(meter?.tint ?? .neutral))
                }

                if appearance.drawsGraph, let meter {
                    graph([meter])
                }
            }
            .opacity(stale ? 0.6 : 1)
            .modifier(ErrorMark(shown: errorMark, color: palette.error))
        }
    }

    private func graph(_ meters: [MenuBarMeter]) -> some View {
        MenuBarGraph(style: appearance.graphStyle, meters: meters, palette: palette)
    }

    private func statusView(_ status: MenuBarStatus) -> some View {
        HStack(spacing: 4) {
            switch status {
            case .setUp, .chooseOrganization:
                Image(systemName: "key.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.foreground)
            case .expired, .error:
                MenuBarErrorGlyph(color: palette.error, size: 14)
            case .loading:
                EmptyView()
            }

            Text(status.title)
                .font(Font(NSFont.menuBarFont(ofSize: 0)))
                .monospacedDigit()
                .foregroundStyle(palette.foreground)
        }
    }
}

private struct ErrorMark: ViewModifier {
    let shown: Bool
    let color: Color

    func body(content: Content) -> some View {
        HStack(spacing: 4) {
            content

            if shown {
                MenuBarErrorGlyph(color: color, size: 12)
            }
        }
    }
}

/// One line per meter, in array order, each led by a tiny letter. A single
/// line has the height to itself, so it uses the menu bar's own text size.
private struct MenuBarText: View {
    let meters: [MenuBarMeter]
    let showsValue: Bool
    let showsCountdown: Bool
    let palette: MenuBarPalette

    private var isSingleLine: Bool { meters.count == 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: -1) {
            ForEach(Array(meters.enumerated()), id: \.offset) { _, meter in
                line(meter)
            }
        }
    }

    private func line(_ meter: MenuBarMeter) -> some View {
        let color = palette.text(meter.tint)
        let text = meter.lineText(showsValue: showsValue, showsCountdown: showsCountdown)

        return HStack(alignment: .firstTextBaseline, spacing: isSingleLine ? 3 : 2) {
            Text(meter.letter)
                .font(.system(size: isSingleLine ? 9 : 7, weight: .bold))
                .foregroundStyle(color.opacity(0.6))

            Text(text)
                .font(isSingleLine ? Font(NSFont.menuBarFont(ofSize: 0)) : .system(size: 9.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }
}

/// A broken ring with an exclamation mark, in the graph's visual language.
private struct MenuBarErrorGlyph: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.08, to: 0.92)
                .stroke(color, style: StrokeStyle(lineWidth: 1.8 * size / 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(0.9 * size / 14)

            Text("!")
                .font(.system(size: 9 * size / 14, weight: .heavy))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}

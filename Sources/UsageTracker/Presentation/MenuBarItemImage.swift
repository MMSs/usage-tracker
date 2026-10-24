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
        _ item: MenuBarItem,
        appearance: MenuBarAppearance,
        displayName: String,
        darkMenuBar: Bool
    ) -> NSImage? {
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
                if appearance.drawsText {
                    MenuBarText(meters: meters, countdown: appearance.countdown, palette: palette)
                }

                if appearance.drawsGraph {
                    graph(meters)
                }
            }
            .opacity(stale ? 0.6 : 1)
            .modifier(ErrorMark(shown: errorMark, color: palette.error))
        case let .money(text, meter, stale, errorMark):
            HStack(spacing: 4) {
                Text(text)
                    .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(palette.text(meter?.tint ?? .neutral))

                if appearance.drawsGraph, let meter {
                    graph([meter])
                }
            }
            .opacity(stale ? 0.6 : 1)
            .modifier(ErrorMark(shown: errorMark, color: palette.error))
        }
    }

    @ViewBuilder
    private func graph(_ meters: [MenuBarMeter]) -> some View {
        switch appearance.graphStyle {
        case .rings:
            MenuBarRing(meters: meters, palette: palette)
        case .bars:
            MenuBarBars(meters: meters, palette: palette)
        }
    }

    private func statusView(_ status: MenuBarStatus) -> some View {
        HStack(spacing: 4) {
            switch status {
            case .setUp:
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
    let countdown: Bool
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
        let text = countdown && meter.countdown != nil ? "\(meter.text) · \(meter.countdown ?? "")" : meter.text

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

/// The last meter is the outer ring, the first the innermost, each filling
/// clockwise from twelve. A meter with a tick draws it across its own ring.
private struct MenuBarRing: View {
    let meters: [MenuBarMeter]
    let palette: MenuBarPalette

    private let diameter: CGFloat = 18
    private let lineWidth: CGFloat = 2.5
    private let gap: CGFloat = 1.5

    var body: some View {
        ZStack {
            ForEach(Array(meters.enumerated()), id: \.offset) { index, meter in
                let depth = CGFloat(meters.count - 1 - index)
                let inset = lineWidth / 2 + depth * (lineWidth + gap)

                arc(meter, inset: inset)

                if let tick = meter.tick {
                    // Crosses its ring and pokes into the gap inside it.
                    Capsule()
                        .fill(palette.tick)
                        .frame(width: 1.5, height: lineWidth + 2)
                        .offset(y: -(diameter / 2 - depth * (lineWidth + gap) - (lineWidth + 2) / 2))
                        .rotationEffect(.degrees(tick * 360))
                }
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private func arc(_ meter: MenuBarMeter, inset: CGFloat) -> some View {
        ZStack {
            Circle()
                .inset(by: inset)
                .stroke(palette.track, lineWidth: lineWidth)

            if let fraction = meter.fraction, fraction > 0 {
                Circle()
                    .inset(by: inset)
                    .trim(from: 0, to: fraction)
                    .stroke(palette.fill(meter.tint), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

/// Top to bottom in array order.
private struct MenuBarBars: View {
    let meters: [MenuBarMeter]
    let palette: MenuBarPalette

    private let width: CGFloat = 28
    private let barHeight: CGFloat = 3.5

    var body: some View {
        VStack(spacing: 3) {
            ForEach(Array(meters.enumerated()), id: \.offset) { _, meter in
                bar(meter)
            }
        }
    }

    private func bar(_ meter: MenuBarMeter) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(palette.track)

            if let fraction = meter.fraction, fraction > 0 {
                Capsule()
                    .fill(palette.fill(meter.tint))
                    .frame(width: max(barHeight, width * fraction))
            }
        }
        .frame(width: width, height: barHeight)
        .overlay(alignment: .leading) {
            if let tick = meter.tick {
                Capsule()
                    .fill(palette.tick)
                    .frame(width: 1.5, height: barHeight + 2)
                    .offset(x: width * tick - 0.75)
            }
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

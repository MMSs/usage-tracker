import SwiftUI

/// The provider's mark, filled in the item's foreground colour. Cursor draws
/// its hexagon cube; Anthropic and OpenAI are placeholder letters until their
/// providers land.
struct ProviderGlyph: Shape {
    let provider: Provider

    func path(in rect: CGRect) -> Path {
        switch provider {
        case .cursor:
            cube(in: rect)
        case .anthropic:
            letterA(in: rect)
        case .openai:
            letterO(in: rect)
        }
    }

    /// A regular hexagon with the three inner edges from the centre to alternating vertices.
    private func cube(in rect: CGRect) -> Path {
        let lineWidth: CGFloat = 1.5
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - lineWidth / 2
        let vertices = (0 ..< 6).map { index -> CGPoint in
            let angle = (-90 + 60 * Double(index)) * .pi / 180
            return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }

        var outline = Path()
        outline.move(to: vertices[0])
        vertices.dropFirst().forEach { outline.addLine(to: $0) }
        outline.closeSubpath()

        for index in [1, 3, 5] {
            outline.move(to: center)
            outline.addLine(to: vertices[index])
        }

        return outline.strokedPath(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }

    private func letterA(in rect: CGRect) -> Path {
        let lineWidth: CGFloat = 2.2
        let inset = lineWidth / 2
        let left = CGPoint(x: rect.minX + inset, y: rect.maxY - inset)
        let apex = CGPoint(x: rect.midX, y: rect.minY + inset)
        let right = CGPoint(x: rect.maxX - inset, y: rect.maxY - inset)
        let barY = rect.minY + rect.height * 0.68

        var strokes = Path()
        strokes.move(to: left)
        strokes.addLine(to: apex)
        strokes.addLine(to: right)
        strokes.move(to: CGPoint(x: rect.minX + rect.width * 0.25, y: barY))
        strokes.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.25, y: barY))

        return strokes.strokedPath(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }

    private func letterO(in rect: CGRect) -> Path {
        let lineWidth: CGFloat = 2.8

        return Path(ellipseIn: rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
            .strokedPath(StrokeStyle(lineWidth: lineWidth))
    }
}

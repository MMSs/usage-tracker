import SwiftUI

/// The provider's mark, filled in the item's foreground colour. Cursor uses
/// its official 2D cube; Anthropic and OpenAI are placeholder letters until
/// their providers land.
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

    /// Cursor's monochrome 2D cube, path data from the CUBE_2D asset in the
    /// brand pack at https://cursor.com/brand. The mark is Cursor's trademark
    /// and identifies the service only.
    private static let cursorCubeViewBox = CGSize(width: 466.73, height: 532.09)
    private static let cursorCube = SVGPath.path(
        "M457.43,125.94L244.42,2.96c-6.84-3.95-15.28-3.95-22.12,0L9.3,125.94c-5.75,3.32-9.3,9.46-9.3,16.11v247.99"
            + "c0,6.65,3.55,12.79,9.3,16.11l213.01,122.98c6.84,3.95,15.28,3.95,22.12,0l213.01-122.98"
            + "c5.75-3.32,9.3-9.46,9.3-16.11v-247.99c0-6.65-3.55-12.79-9.3-16.11h-.01Z"
            + "M444.05,151.99l-205.63,356.16c-1.39,2.4-5.06,1.42-5.06-1.36v-233.21c0-4.66-2.49-8.97-6.53-11.31"
            + "L24.87,145.67c-2.4-1.39-1.42-5.06,1.36-5.06h411.26c5.84,0,9.49,6.33,6.57,11.39h-.01Z"
    )

    private func cube(in rect: CGRect) -> Path {
        SVGPath.fit(Self.cursorCube, viewBox: Self.cursorCubeViewBox, in: rect)
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

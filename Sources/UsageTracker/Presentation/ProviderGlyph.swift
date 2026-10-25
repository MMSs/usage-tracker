import SwiftUI

/// The provider's mark, filled in the item's foreground colour. Cursor uses
/// its official 2D cube; Anthropic uses an original "A\" drawing, not its
/// trademarked logo; OpenAI uses an original hexagon ring, not its
/// trademarked logo.
struct ProviderGlyph: Shape {
    let provider: Provider

    func path(in rect: CGRect) -> Path {
        switch provider {
        case .cursor:
            cube(in: rect)
        case .anthropic:
            anthropicMark(in: rect)
        case .openai:
            openAIMark(in: rect)
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

    /// An original "A\" drawing in the spirit of the Anthropic logotype: a bold
    /// geometric A (flat apex, crossbar at 40% of the cap height, stroke 22% of
    /// it) and a backslash of the same stroke leaning 20 degrees, half a stroke
    /// away. Hand-written polygons in a 100 x 100 box, no font involved. It is
    /// not Anthropic's trademarked logo.
    private static let anthropicViewBox = CGSize(width: 100, height: 100)
    private static let anthropicMark = SVGPath.path(
        "M3,88L29,12L43,12L69,88L51.3,88L43.8,66L28.2,66L20.7,88Z"
            + "M36,43.2L33.9,49.2L38.1,49.2Z"
            + "M51.4,12L69.2,12L96.8,88L79,88Z"
    )

    private func anthropicMark(in rect: CGRect) -> Path {
        SVGPath.fit(Self.anthropicMark, viewBox: Self.anthropicViewBox, in: rect)
    }

    /// An original flat-topped regular hexagon ring in a 100 x 100 box centred
    /// at (50, 50): outer circumradius 48, stroke 18 (inner circumradius
    /// 27.2154), every corner rounded by 6 with a cubic whose controls sit two
    /// thirds of the way to the corner. The inner contour runs the other way so
    /// the non-zero fill leaves the hole open. It is not OpenAI's trademarked logo.
    private static let openAIViewBox = CGSize(width: 100, height: 100)
    private static let openAIMark = SVGPath.path(
        "M95.00,44.80C97.00,48.27 97.00,51.73 95.00,55.20L77.00,86.37C75.00,89.84 72.00,91.57 68.00,91.57"
            + "L32.00,91.57C28.00,91.57 25.00,89.84 23.00,86.37L5.00,55.20C3.00,51.73 3.00,48.27 5.00,44.80"
            + "L23.00,13.63C25.00,10.16 28.00,8.43 32.00,8.43L68.00,8.43C72.00,8.43 75.00,10.16 77.00,13.63Z"
            + "M66.61,31.63C64.61,28.16 61.61,26.43 57.61,26.43L42.39,26.43C38.39,26.43 35.39,28.16 33.39,31.63"
            + "L25.78,44.80C23.78,48.27 23.78,51.73 25.78,55.20L33.39,68.37C35.39,71.84 38.39,73.57 42.39,73.57"
            + "L57.61,73.57C61.61,73.57 64.61,71.84 66.61,68.37L74.22,55.20C76.22,51.73 76.22,48.27 74.22,44.80Z"
    )

    private func openAIMark(in rect: CGRect) -> Path {
        SVGPath.fit(Self.openAIMark, viewBox: Self.openAIViewBox, in: rect)
    }
}

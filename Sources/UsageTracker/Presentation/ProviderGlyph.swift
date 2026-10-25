import SwiftUI

/// The provider's mark, filled in the item's foreground colour. Cursor and
/// OpenAI use their official marks; Anthropic uses an original "A\" drawing,
/// not its trademarked logo.
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

    /// OpenAI's monochrome blossom, path data from the Simple Icons release
    /// 13.21.0 (source https://openai.com/brand) with its arcs rewritten as
    /// cubics (worst deviation 0.009 in the 24 x 24 box). The mark is OpenAI's
    /// trademark and identifies the service only.
    private static let openAIViewBox = CGSize(width: 24, height: 24)
    private static let openAIMark = SVGPath.path(
        "M22.2819,9.8211C22.8248,8.1862 22.6369,6.3967 21.7662,4.9103"
            + "C20.4571,2.6316 17.826,1.4595 15.2564,2.0103C13.8083,0.3995 11.6112,-0.3168 9.492,0.1311"
            + "C7.3728,0.5789 5.6533,2.1229 4.9807,4.1818C3.2928,4.5279 1.836,5.5847 0.983,7.0818"
            + "C-0.3404,9.3568 -0.0401,12.2267 1.7257,14.1784C1.1808,15.8125 1.367,17.6022 2.2367,19.0891"
            + "C3.5475,21.3686 6.1803,22.5406 8.7513,21.9892C9.8948,23.277 11.5377,24.0097 13.2599,24"
            + "C15.8937,24.0024 18.2271,22.3021 19.0317,19.7942C20.7194,19.4475 22.176,18.3908 23.0294,16.8941"
            + "C24.3368,14.6231 24.0351,11.7688 22.2819,9.8212ZM13.2599,22.4292"
            + "C12.2086,22.4309 11.1903,22.0624 10.3835,21.3884L10.5254,21.308L15.3037,18.5498"
            + "C15.5456,18.4079 15.6949,18.149 15.6964,17.8685L15.6964,11.1316L17.7164,12.3002"
            + "C17.7367,12.3105 17.7508,12.3298 17.7544,12.3522L17.7544,17.9348"
            + "C17.7491,20.4148 15.7399,22.424 13.2599,22.4292ZM3.5992,18.3038"
            + "C3.072,17.3934 2.8827,16.3263 3.0646,15.2901L3.2066,15.3753L7.9896,18.1335"
            + "C8.2306,18.2749 8.5292,18.2749 8.7702,18.1335L14.613,14.765L14.613,17.0974"
            + "C14.6119,17.1219 14.5997,17.1445 14.5798,17.1589L9.74,19.9502"
            + "C7.5893,21.1891 4.8416,20.4525 3.5992,18.3038ZM2.3408,7.8956"
            + "C2.8717,6.9794 3.7096,6.2805 4.7063,5.9228L4.7063,11.6C4.7026,11.8793 4.8513,12.1386 5.0942,12.2765"
            + "L10.9086,15.6308L8.8885,16.7993C8.8663,16.8111 8.8397,16.8111 8.8175,16.7993L3.9872,14.0128"
            + "C1.8408,12.7686 1.1047,10.023 2.3408,7.872ZM18.9371,11.7514L13.1038,8.364L15.1192,7.2"
            + "C15.1414,7.1882 15.168,7.1882 15.1902,7.2L20.0205,9.9913"
            + "C21.5281,10.8612 22.3979,12.5234 22.2531,14.258C22.1083,15.9926 20.975,17.4876 19.344,18.0955"
            + "L19.344,12.4183C19.3355,12.1397 19.1808,11.8863 18.937,11.7513ZM20.9478,8.7283L20.8058,8.6431"
            + "L16.0323,5.8613C15.7898,5.719 15.4894,5.719 15.2469,5.8613L9.409,9.2297L9.409,6.8974"
            + "C9.4065,6.8732 9.4174,6.8496 9.4374,6.8359L14.2677,4.0493"
            + "C15.779,3.1787 17.6573,3.2599 19.0877,4.2578C20.5182,5.2556 21.2431,6.9903 20.9479,8.7093Z"
            + "M8.3065,12.863L6.2865,11.6992C6.266,11.6869 6.2521,11.6661 6.2485,11.6425L6.2485,6.0742"
            + "C6.2508,4.3304 7.2605,2.7449 8.8397,2.0054C10.419,1.2659 12.2833,1.5056 13.6242,2.6205L13.4822,2.701"
            + "L8.704,5.459C8.4621,5.6009 8.3128,5.8598 8.3113,6.1403ZM9.4041,10.4976L12.0061,8.9978L14.613,10.4976"
            + "L14.613,13.497L12.0156,14.9967L9.4089,13.497Z"
    )

    private func openAIMark(in rect: CGRect) -> Path {
        SVGPath.fit(Self.openAIMark, viewBox: Self.openAIViewBox, in: rect)
    }
}

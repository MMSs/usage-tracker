import SwiftUI
import Testing
@testable import UsageTracker

@Suite struct SVGPathTests {
    @Test func absoluteCommandsBuildClosedShape() {
        let path = SVGPath.path("M0,0 L10,0 L10,10 Z")

        #expect(path.boundingRect == CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(path.contains(CGPoint(x: 8, y: 2)))
        #expect(!path.contains(CGPoint(x: 2, y: 8)))
    }

    @Test func relativeAndShorthandCommands() {
        let path = SVGPath.path("m1,1 h8 v8 h-8 z")

        #expect(path.boundingRect == CGRect(x: 1, y: 1, width: 8, height: 8))
    }

    @Test func compactNegativeAndDecimalNumbersSplit() {
        let path = SVGPath.path("M0,0l-.5-.5.5.5")

        #expect(path.boundingRect == CGRect(x: -0.5, y: -0.5, width: 0.5, height: 0.5))
    }

    @Test func cubicCurvesAreFilled() {
        let path = SVGPath.path("M0,0 C0,10 10,10 10,0 Z")

        #expect(path.contains(CGPoint(x: 5, y: 5)))
        #expect(!path.contains(CGPoint(x: 5, y: 9)))
    }

    @Test func fitScalesAndCentresWithoutDistortion() {
        let path = SVGPath.path("M0,0 L100,0 L100,200 L0,200 Z")

        let fitted = SVGPath.fit(path, viewBox: CGSize(width: 100, height: 200), in: CGRect(x: 0, y: 0, width: 14, height: 14))
        let bounds = fitted.boundingRect

        #expect(abs(bounds.height - 14) < 0.001)
        #expect(abs(bounds.width - 7) < 0.001)
        #expect(abs(bounds.minX - 3.5) < 0.001)
    }

    @Test func cursorCubeFillsLeftFaceAndRimOnly() {
        let path = ProviderGlyph(provider: .cursor).path(in: CGRect(x: 0, y: 0, width: 466.73, height: 532.09))

        #expect(path.contains(CGPoint(x: 120, y: 330)), "left face is filled")
        #expect(path.contains(CGPoint(x: 420, y: 330)), "right rim is filled")
        #expect(!path.contains(CGPoint(x: 233, y: 200)), "cut-out wedge is empty")
    }

    @Test func cursorCubeFitsMenuBarGlyphBox() {
        let bounds = ProviderGlyph(provider: .cursor).path(in: CGRect(x: 0, y: 0, width: 14, height: 14)).boundingRect

        #expect(bounds.minX >= -0.001 && bounds.maxX <= 14.001)
        #expect(bounds.minY >= -0.001 && bounds.maxY <= 14.001)
        #expect(abs(bounds.height - 14) < 0.05)
    }
}

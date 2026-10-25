import AppKit
import SwiftUI
import Testing
@testable import UsageTracker

@MainActor
@Suite struct MenuBarRenderingTests {
    private func meter(_ letter: String, _ text: String, fraction: Double? = 0.4, tick: Double? = nil, countdown: String? = "2h10", role: MenuBarMeter.Role = .short) -> MenuBarMeter {
        MenuBarMeter(letter: letter, text: text, countdown: countdown, fraction: fraction, tick: tick, tint: .onPace, role: role)
    }

    private var twoMeters: HalfDisplay {
        .meters([meter("S", "41%"), meter("W", "62%", tick: 0.5, role: .long)], stale: false, errorMark: false)
    }

    private var money: HalfDisplay {
        .money(text: "$12.40", meter: meter("$", "$12.40", tick: 0.3, role: .spend), stale: false, errorMark: false)
    }

    private func render(_ item: MenuBarItem, _ appearance: MenuBarAppearance = .default) -> NSImage? {
        MenuBarItemImage.render(item, appearance: appearance, displayName: "Cursor", darkMenuBar: true)
    }

    @Test func batteryShowsWhatRemains() {
        #expect(abs(MenuBarGraphGeometry.batteryFill(0.41)! - 0.59) < 1e-9)
        #expect(MenuBarGraphGeometry.batteryFill(1) == 0)
        #expect(MenuBarGraphGeometry.batteryFill(nil) == nil)
    }

    @Test func anUnknownBatteryMeterIsNotAnEmptyOne() {
        #expect(MenuBarGraphGeometry.batteryLevel(nil) == .unknown)
        #expect(MenuBarGraphGeometry.batteryLevel(1) == .remaining(0))
        guard case let .remaining(remaining) = MenuBarGraphGeometry.batteryLevel(0.41) else {
            Issue.record("a known fraction has a remaining level")
            return
        }
        #expect(abs(remaining - 0.59) < 1e-9)
    }

    @Test func dialsAreWiderThanRingsBecauseTheySitSideBySide() {
        #expect(MenuBarGraphGeometry.size(.dials, meterCount: 2).width == 35)
        #expect(MenuBarGraphGeometry.size(.dials, meterCount: 1).width == 16)
    }

    @Test func segmentsLightOneBlockPerTenthStarted() {
        #expect(MenuBarGraphGeometry.litSegments(0) == 0)
        #expect(MenuBarGraphGeometry.litSegments(0.001) == 1)
        #expect(MenuBarGraphGeometry.litSegments(0.3) == 3)
        #expect(MenuBarGraphGeometry.litSegments(0.31) == 4)
        #expect(MenuBarGraphGeometry.litSegments(1.4) == 10)
        #expect(MenuBarGraphGeometry.litSegments(nil) == 0)
        #expect(MenuBarGraphGeometry.litSegments(.nan) == 0)
        #expect(MenuBarGraphGeometry.litSegments(-0.2) == 0)
    }

    @Test func segmentsStackTwoRowsOrDrawOne() {
        #expect(MenuBarGraphGeometry.size(.segments, meterCount: 2) == CGSize(width: 42.1, height: 14))
        #expect(MenuBarGraphGeometry.size(.segments, meterCount: 1) == CGSize(width: 42.1, height: 6))
    }

    private let sparkSize = CGSize(width: 40, height: 16)
    private let sparkNow = Date(timeIntervalSince1970: 1_800_000_000)

    private func sample(minutesAgo: Double, _ percent: UInt8) -> UsageSample {
        UsageSample(date: sparkNow.addingTimeInterval(-minutesAgo * 60), percent: percent)
    }

    private func sparkline(_ samples: [UsageSample]?, current: Double?) -> [CGPoint] {
        MenuBarGraphGeometry.sparklinePoints(samples: samples, current: current, now: sparkNow, size: sparkSize)
    }

    @Test func aSparklineEndsAtTheLiveValue() throws {
        let points = sparkline([sample(minutesAgo: 30, 20)], current: 0.4)
        let last = try #require(points.last)

        #expect(points.count == 2)
        #expect(abs(last.x - 40) < 1e-9)
        #expect(abs(last.y - 16 * 0.6) < 1e-9)
    }

    @Test func aSparklineLeavesOutWhatIsOlderThanTwelveHours() {
        let points = sparkline([sample(minutesAgo: 13 * 60, 90), sample(minutesAgo: 30, 20)], current: 0.4)

        #expect(points.count == 2)
        #expect(!points.contains { abs($0.y - 16 * 0.1) < 1e-9 })
    }

    @Test func aResetShowsAsADrop() throws {
        let points = sparkline([sample(minutesAgo: 120, 80), sample(minutesAgo: 60, 2)], current: 0.02)
        let high = try #require(points.firstIndex { abs($0.y - 16 * 0.2) < 1e-9 })
        let low = try #require(points.firstIndex { abs($0.y - 16 * 0.98) < 1e-9 })

        #expect(low > high)
        #expect(points.map(\.x) == points.map(\.x).sorted())
    }

    @Test func aSparklineHasAtMostOnePointPerColumn() {
        let samples = (0..<1_440).map { sample(minutesAgo: Double($0), UInt8($0 % 100)) }
        let points = sparkline(samples, current: 0.5)
        let columns = points.map { Int($0.x.rounded(.down)) }

        #expect(points.count <= 41)
        #expect(Set(columns).count == columns.count)
        #expect(points.last == CGPoint(x: 40, y: 8))
    }

    @Test func aMeterWithoutHistoryDrawsFlat() {
        #expect(sparkline(nil, current: 0.5) == [CGPoint(x: 0, y: 8), CGPoint(x: 40, y: 8)])
    }

    @Test func aTrackedMeterWithNoSamplesYetDrawsOnlyItsEnd() {
        #expect(sparkline([], current: 0.5) == [CGPoint(x: 40, y: 8)])
    }

    @Test func anUnknownValueDrawsNothing() {
        #expect(sparkline([sample(minutesAgo: 30, 20)], current: nil).isEmpty)
        #expect(sparkline(nil, current: nil).isEmpty)
    }

    @Test func aSparklineStaysInItsBox() {
        let points = sparkline([sample(minutesAgo: 30, 255), sample(minutesAgo: 10, 255)], current: 1.0)
            + sparkline(nil, current: 7)
            + sparkline([sample(minutesAgo: 30, 0)], current: -3)

        for point in points {
            #expect((0...40).contains(point.x) && (0...16).contains(point.y))
        }
    }

    @Test func sparklineSizeIsFortyBySixteen() {
        #expect(MenuBarGraphGeometry.size(.sparkline, meterCount: 1) == sparkSize)
        #expect(MenuBarGraphGeometry.size(.sparkline, meterCount: 2) == sparkSize)
    }

    @Test func batteryStillReadsPercentUsed() {
        let item = MenuBarItem(provider: .anthropic, subscription: twoMeters, api: nil)
        #expect(item.visible(in: MenuBarAppearance(graphStyle: .battery)).accessibilityText(displayName: "Anthropic") == "Anthropic, S 41%, W 62%")
    }

    @Test func everyGraphStyleDrawsAtItsOwnWidth() throws {
        for style in MenuBarGraphStyle.allCases {
            for count in [1, 2] {
                for tick in [nil, 0.5] as [Double?] {
                    for colored in [true, false] {
                        let meters = Array([meter("S", "41%", tick: tick, role: .short), meter("W", "62%", tick: tick, role: .long)].prefix(count))
                        let item = MenuBarItem(provider: .anthropic, subscription: .meters(meters, stale: false, errorMark: false), api: nil)
                        let appearance = MenuBarAppearance(showText: false, countdown: false, showGraph: true, graphStyle: style, colored: colored)
                        let image = try #require(render(item, appearance))
                        // Glyph 14, spacing 4, then the graph alone.
                        let size = MenuBarGraphGeometry.size(style, meterCount: count)
                        #expect(abs(image.size.width - (18 + size.width)) < 0.5, "\(style) with \(count) meters")
                        #expect(size.height <= 18)
                    }
                }
            }
        }
    }

    @Test func everyCombinationRenders() throws {
        let item = MenuBarItem(provider: .cursor, subscription: twoMeters, api: money)

        for style in MenuBarGraphStyle.allCases {
            for text in [true, false] {
                for countdown in [true, false] {
                    for graph in [true, false] where text || countdown || graph {
                        for colored in [true, false] {
                            let appearance = MenuBarAppearance(
                                showText: text, countdown: countdown, showGraph: graph, graphStyle: style, colored: colored
                            )
                            let image = try #require(render(item, appearance))

                            #expect(image.size.width > 0)
                            #expect(image.isTemplate == !colored)
                        }
                    }
                }
            }
        }
    }

    @Test func countdownShowsWithoutText() throws {
        let item = MenuBarItem(provider: .anthropic, subscription: twoMeters, api: nil)
        let graphOnly = MenuBarAppearance(showText: false, countdown: false, showGraph: true)
        let graphAndCountdown = MenuBarAppearance(showText: false, countdown: true, showGraph: true)

        #expect(try #require(render(item, graphAndCountdown)).size.width > (try #require(render(item, graphOnly)).size.width))
    }

    @Test func theSpendAmountHidesWithShowText() throws {
        let item = MenuBarItem(provider: .openai, subscription: nil, api: money)
        let withText = MenuBarAppearance(showText: true, countdown: false, showGraph: true)
        let withoutText = MenuBarAppearance(showText: false, countdown: true, showGraph: true)

        #expect(try #require(render(item, withoutText)).size.width < (try #require(render(item, withText)).size.width))
    }

    @Test func singleMeterItemIsNarrowerThanTwoMeterItem() throws {
        let one = MenuBarItem(
            provider: .cursor,
            subscription: .meters([meter("C", "∞", fraction: nil, role: .long)], stale: false, errorMark: false),
            api: nil
        )
        let two = MenuBarItem(provider: .cursor, subscription: twoMeters, api: nil)

        let oneWidth = try #require(render(one)).size.width
        let twoWidth = try #require(render(two)).size.width

        #expect(oneWidth < twoWidth)
    }

    @Test func dividerAddsWidth() throws {
        let alone = MenuBarItem(provider: .cursor, subscription: twoMeters, api: nil)
        let both = MenuBarItem(provider: .cursor, subscription: twoMeters, api: money)

        #expect(try #require(render(both)).size.width > (try #require(render(alone)).size.width))
    }

    @Test func hidingAHalfNarrowsTheImage() throws {
        let item = MenuBarItem(provider: .cursor, subscription: twoMeters, api: money)
        var hidden = MenuBarAppearance.default
        hidden.showAPISpend = false

        #expect(try #require(render(item, hidden)).size.width < (try #require(render(item)).size.width))
    }

    @Test func statusStatesRender() throws {
        for status in [MenuBarStatus.setUp, .chooseOrganization, .expired, .error, .loading] {
            let item = MenuBarItem(provider: .anthropic, subscription: .status(status), api: nil)

            #expect(try #require(render(item)).size.width > 0)
        }
    }

    @Test func templateFlagFollowsColorOnlyWhenSomethingCanBeColored() throws {
        let colored = MenuBarAppearance(colored: true)
        let loading = MenuBarItem(provider: .cursor, subscription: .status(.loading), api: nil)
        let expired = MenuBarItem(provider: .cursor, subscription: .status(.expired), api: nil)

        #expect(MenuBarItemImage.isColored(loading, appearance: colored) == false)
        let choose = MenuBarItem(provider: .anthropic, subscription: .status(.chooseOrganization), api: nil)
        #expect(MenuBarItemImage.isColored(choose, appearance: colored) == false)
        #expect(MenuBarItemImage.isColored(expired, appearance: colored))
        #expect(try #require(render(loading, colored)).isTemplate)
        #expect(try #require(render(expired, colored)).isTemplate == false)
    }

    @Test func staleAndErrorMarkRender() throws {
        let plain = MenuBarItem(provider: .cursor, subscription: .meters([meter("S", "41%")], stale: false, errorMark: false), api: nil)
        let marked = MenuBarItem(provider: .cursor, subscription: .meters([meter("S", "41%")], stale: true, errorMark: true), api: nil)

        #expect(try #require(render(marked)).size.width > (try #require(render(plain)).size.width))
    }

    @Test func glyphPathsAreNonEmpty() {
        for provider in Provider.allCases {
            #expect(!ProviderGlyph(provider: provider).path(in: CGRect(x: 0, y: 0, width: 14, height: 14)).isEmpty)
        }
    }

    @Test func anthropicGlyphFillsTheBoxWidth() {
        let box = CGRect(x: 0, y: 0, width: 14, height: 14)
        let bounds = ProviderGlyph(provider: .anthropic).path(in: box).boundingRect

        #expect(bounds.width >= box.width * 0.9)
        #expect(bounds.minX >= box.minX && bounds.maxX <= box.maxX)
        #expect(bounds.minY >= box.minY && bounds.maxY <= box.maxY)
    }

    @Test func openAIGlyphIsTheBlossom() {
        let box = CGRect(x: 0, y: 0, width: 100, height: 100)
        let path = ProviderGlyph(provider: .openai).path(in: box)

        #expect(path.boundingRect.width >= box.width * 0.9)
        #expect(path.boundingRect.height >= box.height * 0.9)
        // The blossom's knot leaves a hexagonal hole at its centre.
        #expect(!path.contains(CGPoint(x: box.midX, y: box.midY)))
    }
}

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

    @Test(arguments: [
        (MenuBarGraphStyle.rings, CGSize(width: 18, height: 18), CGSize(width: 18, height: 18)),
        (.bars, CGSize(width: 28, height: 3.5), CGSize(width: 28, height: 10)),
        (.battery, CGSize(width: 44, height: 14), CGSize(width: 44, height: 14)),
        (.gauge, CGSize(width: 24, height: 14), CGSize(width: 24, height: 14)),
        (.segments, CGSize(width: 42.1, height: 6), CGSize(width: 42.1, height: 14)),
        (.columns, CGSize(width: 4.5, height: 16), CGSize(width: 14, height: 16)),
        (.dials, CGSize(width: 16, height: 16), CGSize(width: 35, height: 16)),
    ])
    func everyStyleKeepsTheSpecSize(style: MenuBarGraphStyle, one: CGSize, two: CGSize) {
        for (count, expected) in [(1, one), (2, two)] {
            let size = MenuBarGraphGeometry.size(style, meterCount: count)

            #expect(abs(size.width - expected.width) < 1e-9)
            #expect(abs(size.height - expected.height) < 1e-9)
        }
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

    @Test func batteryStillReadsPercentUsed() {
        let item = MenuBarItem(provider: .anthropic, subscription: twoMeters, api: nil)
        #expect(item.visible(in: MenuBarAppearance(graphStyle: .battery), halves: .all).accessibilityText(displayName: "Anthropic") == "Anthropic, S 41%, W 62%")
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
                    for graph in [true, false] {
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

    private let allOff = MenuBarAppearance(showText: false, countdown: false, showGraph: false)

    @Test func allOffLeavesOnlyTheLogo() throws {
        let withBudget = MenuBarItem(provider: .openai, subscription: nil, api: money)
        let meters = MenuBarItem(provider: .anthropic, subscription: twoMeters, api: nil)

        #expect(try #require(render(meters, allOff)).size.width == 14)
        #expect(try #require(render(withBudget, allOff)).size.width == 14)
    }

    @Test func aStatusStillDrawsWithEverythingOff() throws {
        let item = MenuBarItem(provider: .anthropic, subscription: .status(.error), api: nil)

        #expect(try #require(render(item, allOff)).size.width > 14)
        #expect(HalfView.drawsSomething(.status(.loading), appearance: allOff))
    }

    @Test func noDividerWhenOneHalfDrawsNothing() throws {
        let both = MenuBarItem(provider: .cursor, subscription: twoMeters, api: money)
        let onlyText = MenuBarAppearance(showText: true, countdown: false, showGraph: false)
        let spendHidden = MenuBarAppearance(showText: false, countdown: true, showGraph: true)
        let noMeterMoney = HalfDisplay.money(text: "$1", meter: nil, stale: false, errorMark: false)

        #expect(HalfView.drawsSomething(twoMeters, appearance: onlyText))
        #expect(!HalfView.drawsSomething(twoMeters, appearance: allOff))
        #expect(HalfView.drawsSomething(money, appearance: onlyText))
        #expect(HalfView.drawsSomething(money, appearance: spendHidden))
        #expect(!HalfView.drawsSomething(noMeterMoney, appearance: allOff))
        #expect(HalfView.drawsSomething(noMeterMoney, appearance: MenuBarAppearance(showText: false, countdown: false, showGraph: true)))

        // Money with a budget, graph off, text off: nothing to draw, so the
        // subscription's width must not include a divider.
        let moneyBlank = MenuBarAppearance(showText: false, countdown: true, showGraph: false)
        let subOnly = MenuBarItem(provider: .cursor, subscription: twoMeters, api: nil)
        #expect(try #require(render(both, moneyBlank)).size.width == (try #require(render(subOnly, moneyBlank)).size.width))
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
        let hidden = MenuBarItemImage.render(
            item, appearance: .default, halves: MenuBarHalves(subscription: true, api: false),
            displayName: "Cursor", darkMenuBar: true
        )

        #expect(try #require(hidden).size.width < (try #require(render(item)).size.width))
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

    @Test func theBadgeDoesNotWidenTheItem() throws {
        let plain = MenuBarItem(provider: .cursor, subscription: twoMeters, api: nil)
        let badged = MenuBarItem(provider: .cursor, subscription: twoMeters, api: nil, logoBadge: true)

        #expect(try #require(render(badged)).size.width == (try #require(render(plain)).size.width))
    }

    @Test func aBadgedLogoIsColoredWhenColoredIsOn() throws {
        let badged = MenuBarItem(provider: .cursor, subscription: nil, api: nil, logoBadge: true)
        let colored = MenuBarAppearance(colored: true)

        #expect(MenuBarItemImage.isColored(badged, appearance: colored))
        #expect(try #require(render(badged, colored)).isTemplate == false)
    }

    @Test func aBadgedLogoIsTemplateOtherwise() throws {
        let badged = MenuBarItem(provider: .cursor, subscription: nil, api: nil, logoBadge: true)

        #expect(MenuBarItemImage.isColored(badged, appearance: MenuBarAppearance(colored: false)) == false)
        #expect(try #require(render(badged, MenuBarAppearance(colored: false))).isTemplate)
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

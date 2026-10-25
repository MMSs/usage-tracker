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

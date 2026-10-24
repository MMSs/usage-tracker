import AppKit
import SwiftUI
import Testing
@testable import UsageTracker

@MainActor
@Suite struct MenuBarRenderingTests {
    private func meter(_ letter: String, _ text: String, fraction: Double? = 0.4, tick: Double? = nil, countdown: String? = "2h10") -> MenuBarMeter {
        MenuBarMeter(letter: letter, text: text, countdown: countdown, fraction: fraction, tick: tick, tint: .onPace)
    }

    private var twoMeters: HalfDisplay {
        .meters([meter("S", "41%"), meter("W", "62%", tick: 0.5)], stale: false, errorMark: false)
    }

    private var money: HalfDisplay {
        .money(text: "$12.40", meter: meter("$", "$12.40", tick: 0.3), stale: false, errorMark: false)
    }

    private func render(_ item: MenuBarItem, _ appearance: MenuBarAppearance = .default) -> NSImage? {
        MenuBarItemImage.render(item, appearance: appearance, displayName: "Cursor", darkMenuBar: true)
    }

    @Test func everyCombinationRenders() throws {
        let item = MenuBarItem(provider: .cursor, subscription: twoMeters, api: money)

        for style in MenuBarGraphStyle.allCases {
            for text in [true, false] {
                for graph in [true, false] where text || graph {
                    for colored in [true, false] {
                        let appearance = MenuBarAppearance(showText: text, countdown: text, showGraph: graph, graphStyle: style, colored: colored)
                        let image = try #require(render(item, appearance))

                        #expect(image.size.width > 0)
                        #expect(image.isTemplate == !colored)
                    }
                }
            }
        }
    }

    @Test func singleMeterItemIsNarrowerThanTwoMeterItem() throws {
        let one = MenuBarItem(
            provider: .cursor,
            subscription: .meters([meter("C", "∞", fraction: nil)], stale: false, errorMark: false),
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

    @Test func statusStatesRender() throws {
        for status in [MenuBarStatus.setUp, .expired, .error, .loading] {
            let item = MenuBarItem(provider: .anthropic, subscription: .status(status), api: nil)

            #expect(try #require(render(item)).size.width > 0)
        }
    }

    @Test func templateFlagFollowsColorOnlyWhenSomethingCanBeColored() throws {
        let colored = MenuBarAppearance(colored: true)
        let loading = MenuBarItem(provider: .cursor, subscription: .status(.loading), api: nil)
        let expired = MenuBarItem(provider: .cursor, subscription: .status(.expired), api: nil)

        #expect(MenuBarItemImage.isColored(loading, appearance: colored) == false)
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
}

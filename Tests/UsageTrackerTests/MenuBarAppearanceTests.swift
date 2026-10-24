import Testing
@testable import UsageTracker

@Suite struct MenuBarAppearanceTests {
    @Test func refusesToHideBothParts() {
        #expect(MenuBarAppearance(showText: true, showGraph: false).showingText(false).showText == true)
        #expect(MenuBarAppearance(showText: false, showGraph: true).showingGraph(false).showGraph == true)
    }

    @Test func hidesOnePartWhenTheOtherStays() {
        #expect(MenuBarAppearance().showingText(false).showText == false)
        #expect(MenuBarAppearance().showingGraph(false).showGraph == false)
        #expect(MenuBarAppearance(showText: false, showGraph: false).showingText(true).showText == true)
    }

    @Test func defaults() {
        let appearance = MenuBarAppearance.default
        #expect(appearance.showText && appearance.showGraph)
        #expect(!appearance.countdown && !appearance.colored)
        #expect(appearance.graphStyle == .rings)
        #expect(MenuBarGraphStyle.allCases.map(\.title) == ["Rings", "Bars"])
    }

    @Test func drawsOnlyWhatIsShown() {
        #expect(MenuBarAppearance(showText: true, showGraph: false).drawsText)
        #expect(!MenuBarAppearance(showText: true, showGraph: false).drawsGraph)
        #expect(MenuBarAppearance(showText: false, showGraph: true).drawsGraph)
    }
}

import Foundation
import Testing
@testable import UsageTracker

@Suite struct MenuBarAppearanceTests {
    @Test func limitsTitlesNameTheProvidersMeters() {
        let cursor = ProviderRegistry.descriptor(for: .cursor).meterNames
        #expect(MenuBarLimits.allCases.map { $0.title(names: cursor) } == ["Both", "Today", "Cycle"])
        #expect(MenuBarLimits.allCases.map { $0.title(names: ProviderRegistry.descriptor(for: .anthropic).meterNames) } == ["Both", "Session", "Weekly"])
        #expect(MenuBarLimits.allCases.map { $0.title(names: nil) } == ["Both", "Short", "Long"])
    }

    @Test func refusesToHideBothParts() {
        #expect(MenuBarAppearance(showText: true, showGraph: false).showingText(false).showText == true)
        #expect(MenuBarAppearance(showText: false, showGraph: true).showingGraph(false).showGraph == true)
    }

    @Test func hidesOnePartWhenTheOtherStays() {
        #expect(MenuBarAppearance().showingText(false).showText == false)
        #expect(MenuBarAppearance().showingGraph(false).showGraph == false)
        #expect(MenuBarAppearance(showText: false, showGraph: false).showingText(true).showText == true)
    }

    @Test func countdownCountsAsAVisiblePart() {
        let countdownOnly = MenuBarAppearance(showText: false, countdown: true, showGraph: false)
        #expect(countdownOnly.showingCountdown(false).countdown == true)
        #expect(MenuBarAppearance(showText: true, countdown: true, showGraph: false).showingText(false).showText == false)
        #expect(MenuBarAppearance(showText: false, countdown: true, showGraph: true).showingGraph(false).showGraph == false)
        #expect(MenuBarAppearance(showText: true, countdown: true, showGraph: false).showingCountdown(false).countdown == false)
        #expect(MenuBarAppearance(showText: false, countdown: false, showGraph: true).showingCountdown(true).countdown == true)
    }

    @Test func theSpendAmountFollowsShowTextUnlessNothingElseWouldShow() {
        let textOff = MenuBarAppearance(showText: false, countdown: true, showGraph: true)
        #expect(!textOff.showsSpendAmount(hasMeter: true))
        // No budget, so no ring: the amount is all the API side has.
        #expect(textOff.showsSpendAmount(hasMeter: false))
        #expect(MenuBarAppearance(showText: false, countdown: true, showGraph: false).showsSpendAmount(hasMeter: true))
        #expect(MenuBarAppearance(showText: true, showGraph: true).showsSpendAmount(hasMeter: true))
    }

    @Test func refusesToHideBothHalves() {
        let apiHidden = MenuBarAppearance().showingAPISpend(false)
        #expect(!apiHidden.showAPISpend)
        #expect(apiHidden.showingPlanUsage(false).showPlanUsage)
        #expect(MenuBarAppearance().showingPlanUsage(false).showingAPISpend(false).showAPISpend)
        #expect(apiHidden.showingAPISpend(true).showAPISpend)
    }

    @Test func anOverrideSavedBeforeTheVisibilityFieldsKeepsItsValues() throws {
        let json = #"{"showText":false,"countdown":true,"showGraph":true,"graphStyle":"bars","colored":true}"#
        let appearance = try JSONDecoder().decode(MenuBarAppearance.self, from: Data(json.utf8))
        #expect(appearance == MenuBarAppearance(showText: false, countdown: true, showGraph: true, graphStyle: .bars, colored: true))
        #expect(appearance.showPlanUsage && appearance.showAPISpend && appearance.limits == .both)
    }

    @Test func unknownStoredValuesFallBackInsteadOfDroppingTheOverride() throws {
        let json = #"{"showText":true,"countdown":false,"showGraph":true,"graphStyle":"hexagons","colored":false,"limits":"middle"}"#
        let appearance = try JSONDecoder().decode(MenuBarAppearance.self, from: Data(json.utf8))
        #expect(appearance.graphStyle == .rings)
        #expect(appearance.limits == .both)
    }

    @Test func defaults() {
        let appearance = MenuBarAppearance.default
        #expect(appearance.showText && appearance.showGraph)
        #expect(!appearance.countdown && !appearance.colored)
        #expect(appearance.graphStyle == .rings)
        #expect(appearance.showPlanUsage && appearance.showAPISpend && appearance.limits == .both)
        #expect(MenuBarGraphStyle.allCases.map(\.title) == ["Rings", "Bars", "Battery", "Columns"])
    }

    @Test func drawsOnlyWhatIsShown() {
        #expect(MenuBarAppearance(showText: true, showGraph: false).drawsText)
        #expect(!MenuBarAppearance(showText: true, showGraph: false).drawsGraph)
        #expect(MenuBarAppearance(showText: false, showGraph: true).drawsGraph)
        #expect(MenuBarAppearance(showText: false, countdown: true, showGraph: true).drawsCountdown)
        #expect(!MenuBarAppearance(showText: true, countdown: false, showGraph: true).drawsCountdown)
    }
}

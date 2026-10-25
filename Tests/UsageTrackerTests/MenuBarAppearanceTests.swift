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

    @Test func everySwitchCanBeOff() {
        let allOff = MenuBarAppearance(showText: false, countdown: false, showGraph: false)
        #expect(!allOff.drawsText && !allOff.drawsCountdown && !allOff.drawsGraph)
    }

    @Test func theAmountHidesWhenTextAndGraphAreOff() {
        let appearance = MenuBarAppearance(showText: false, countdown: true, showGraph: false)
        #expect(!appearance.showsSpendAmount(hasMeter: true))
        #expect(!appearance.showsSpendAmount(hasMeter: false))
    }

    @Test func theAmountShowsWithAGraphButNoBudget() {
        let appearance = MenuBarAppearance(showText: false, countdown: false, showGraph: true)
        #expect(appearance.showsSpendAmount(hasMeter: false))
        #expect(!appearance.showsSpendAmount(hasMeter: true))
    }

    @Test func theAmountFollowsShowText() {
        #expect(MenuBarAppearance(showText: true, showGraph: false).showsSpendAmount(hasMeter: true))
        #expect(MenuBarAppearance(showText: true, showGraph: true).showsSpendAmount(hasMeter: true))
    }

    @Test func anOverrideSavedBeforeTheVisibilityFieldsKeepsItsValues() throws {
        let json = #"{"showText":false,"countdown":true,"showGraph":true,"graphStyle":"bars","colored":true}"#
        let appearance = try JSONDecoder().decode(MenuBarAppearance.self, from: Data(json.utf8))
        #expect(appearance == MenuBarAppearance(showText: false, countdown: true, showGraph: true, graphStyle: .bars, colored: true))
        #expect(appearance.limits == .both)
    }

    @Test func unknownStoredValuesFallBackInsteadOfDroppingTheOverride() throws {
        let json = #"{"showText":true,"countdown":false,"showGraph":true,"graphStyle":"hexagons","colored":false,"limits":"middle"}"#
        let appearance = try JSONDecoder().decode(MenuBarAppearance.self, from: Data(json.utf8))
        #expect(appearance.graphStyle == .rings)
        #expect(appearance.limits == .both)
    }

    @Test(arguments: ["pie", "sparkline"])
    func aRemovedStyleLoadsAsRings(raw: String) throws {
        let json = #"{"showText":false,"countdown":true,"showGraph":true,"graphStyle":"\#(raw)","colored":true}"#
        let appearance = try JSONDecoder().decode(MenuBarAppearance.self, from: Data(json.utf8))
        #expect(appearance.graphStyle == .rings)
        #expect(!appearance.showText)
        #expect(appearance.countdown && appearance.colored)
    }

    @Test func anOverrideWithTheOldHalfKeysStillDecodes() throws {
        let json = #"{"showText":false,"countdown":true,"showGraph":true,"graphStyle":"bars","colored":true,"showPlanUsage":false,"showAPISpend":false,"limits":"long"}"#
        let appearance = try JSONDecoder().decode(MenuBarAppearance.self, from: Data(json.utf8))
        #expect(appearance == MenuBarAppearance(showText: false, countdown: true, showGraph: true, graphStyle: .bars, colored: true, limits: .long))
    }

    @Test func defaults() {
        let appearance = MenuBarAppearance.default
        #expect(appearance.showText && appearance.showGraph)
        #expect(!appearance.countdown && !appearance.colored)
        #expect(appearance.graphStyle == .rings)
        #expect(appearance.limits == .both)
        #expect(MenuBarGraphStyle.allCases.map(\.title) == ["Rings", "Bars", "Battery", "Gauge", "Segments", "Columns", "Dials"])
    }

    @Test func drawsOnlyWhatIsShown() {
        #expect(MenuBarAppearance(showText: true, showGraph: false).drawsText)
        #expect(!MenuBarAppearance(showText: true, showGraph: false).drawsGraph)
        #expect(MenuBarAppearance(showText: false, showGraph: true).drawsGraph)
        #expect(MenuBarAppearance(showText: false, countdown: true, showGraph: true).drawsCountdown)
        #expect(!MenuBarAppearance(showText: true, countdown: false, showGraph: true).drawsCountdown)
    }
}

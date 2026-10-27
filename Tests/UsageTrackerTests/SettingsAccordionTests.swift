import Testing
@testable import UsageTracker

struct SettingsAccordionTests {
    @Test
    func theFirstSectionStartsOpen() {
        let accordion = SettingsAccordion(titles: ["Alerts", "Appearance"])

        #expect(accordion.isOpen("Alerts"))
        #expect(!accordion.isOpen("Appearance"))
        #expect(accordion.isCollapsible)
    }

    @Test
    func openingOneClosesTheOther() {
        var accordion = SettingsAccordion(titles: ["Alerts", "Appearance"])

        accordion.open("Appearance")

        #expect(accordion.isOpen("Appearance"))
        #expect(!accordion.isOpen("Alerts"))
    }

    @Test
    func expandingASectionOpensIt() {
        var accordion = SettingsAccordion(titles: ["Alerts", "Appearance"])

        accordion.setExpanded(true, "Appearance")

        #expect(accordion.isOpen("Appearance"))
        #expect(!accordion.isOpen("Alerts"))
    }

    /// One section always stays open, so collapsing the open one is refused.
    @Test
    func collapsingTheOpenSectionKeepsItOpen() {
        var accordion = SettingsAccordion(titles: ["Alerts", "Appearance"])

        accordion.setExpanded(false, "Alerts")

        #expect(accordion.isOpen("Alerts"))
    }

    @Test
    func aSingleSectionIsAlwaysOpenAndNotCollapsible() {
        var accordion = SettingsAccordion(titles: ["Refresh"])

        accordion.open("Other")

        #expect(accordion.isOpen("Refresh"))
        #expect(!accordion.isCollapsible)
    }

    @Test
    func anUnknownTitleChangesNothing() {
        var accordion = SettingsAccordion(titles: ["Menu bar", "Alerts", "Startup"], open: "Alerts")

        accordion.open("Nope")

        #expect(accordion.isOpen("Alerts"))
    }

    @Test
    func anUnknownStartingTitleFallsBackToTheFirst() {
        let accordion = SettingsAccordion(titles: ["Menu bar", "Alerts"], open: "Nope")

        #expect(accordion.isOpen("Menu bar"))
    }
}

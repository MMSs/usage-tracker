import Testing
@testable import UsageTracker

struct SettingsAccordionTests {
    /// Several sections start collapsed, so the list of headings is what the user sees first.
    @Test
    func everySectionStartsCollapsed() {
        let accordion = SettingsAccordion(titles: ["Alerts", "Appearance"])

        #expect(!accordion.isOpen("Alerts"))
        #expect(!accordion.isOpen("Appearance"))
        #expect(accordion.open == nil)
        #expect(accordion.isCollapsible)
    }

    @Test
    func aChosenStartingSectionStartsOpen() {
        let accordion = SettingsAccordion(titles: ["Alerts", "Appearance"], open: "Appearance")

        #expect(accordion.isOpen("Appearance"))
        #expect(!accordion.isOpen("Alerts"))
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

    @Test
    func collapsingTheOpenSectionLeavesAllCollapsed() {
        var accordion = SettingsAccordion(titles: ["Alerts", "Appearance"], open: "Alerts")

        accordion.setExpanded(false, "Alerts")

        #expect(!accordion.isOpen("Alerts"))
        #expect(!accordion.isOpen("Appearance"))
        #expect(accordion.open == nil)
    }

    @Test
    func collapsingAClosedSectionChangesNothing() {
        var accordion = SettingsAccordion(titles: ["Alerts", "Appearance"], open: "Alerts")

        accordion.setExpanded(false, "Appearance")

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
    func anUnknownStartingTitleLeavesAllCollapsed() {
        let accordion = SettingsAccordion(titles: ["Menu bar", "Alerts"], open: "Nope")

        #expect(!accordion.isOpen("Menu bar"))
        #expect(!accordion.isOpen("Alerts"))
    }
}

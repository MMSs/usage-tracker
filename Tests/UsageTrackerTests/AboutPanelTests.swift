import AppKit
import Testing
@testable import UsageTracker

@MainActor
struct AboutPanelTests {
    private func release(_ version: String) -> BuildInfo {
        BuildInfo(infoDictionary: ["CFBundleShortVersionString": version])
    }

    @Test func aReleaseShowsItsVersion() {
        let options = AboutPanel.options(build: release("1.0.0"))
        #expect(options[.applicationName] as? String == "Usage Tracker")
        #expect(options[.applicationVersion] as? String == "1.0.0")
        #expect(options[.version] as? String == "")
        #expect(options[NSApplication.AboutPanelOptionKey(rawValue: "Copyright")] as? String == "© 2026 Mohab. MIT License.")
        #expect(options[.credits] is NSAttributedString)
    }

    @Test func aSourceBuildShowsDev() {
        let options = AboutPanel.options(build: BuildInfo(infoDictionary: nil))
        #expect(options[.applicationVersion] as? String == "dev")
    }

    @Test func creditsLinkTheRepo() throws {
        let credits = AboutPanel.credits()
        let text = credits.string as NSString
        #expect(text.contains("github.com/MMSs/usage-tracker"))
        #expect(text.contains("Not affiliated with Cursor, Anthropic or OpenAI."))

        let repo = text.range(of: "github.com/MMSs/usage-tracker")
        #expect(credits.attribute(.link, at: repo.location, effectiveRange: nil) as? URL
            == URL(string: "https://github.com/MMSs/usage-tracker"))

        let labels: [NSColor] = [.labelColor, .secondaryLabelColor]
        for index in 0..<credits.length {
            let color = try #require(credits.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor)
            #expect(labels.contains(color))
        }
    }

    @Test func theStandardAboutItemIsRetargeted() throws {
        let menu = NSMenu()
        let about = NSMenuItem(title: "About Usage Tracker", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(about)
        menu.addItem(quit)
        let host = NSMenuItem()
        host.submenu = menu
        let main = NSMenu()
        main.addItem(host)

        AboutPanel.replaceAboutItem(in: main)

        #expect(about.action == #selector(AboutPanel.Responder.showAbout(_:)))
        #expect(about.target is AboutPanel.Responder)
        #expect(quit.action == #selector(NSApplication.terminate(_:)))
    }

    @Test func aMenuRebuiltLaterIsRetargetedWhenItOpens() {
        let center = NotificationCenter()
        let main = NSMenu()
        let host = NSMenuItem()
        host.submenu = NSMenu()
        main.addItem(host)
        let observer = AboutPanel.MenuTrackingObserver(center: center) { main }

        // The menu is rebuilt after launch with the standard item again.
        let about = NSMenuItem(title: "About Usage Tracker", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        host.submenu?.addItem(about)
        center.post(name: NSMenu.didBeginTrackingNotification, object: main)

        #expect(about.action == #selector(AboutPanel.Responder.showAbout(_:)))
        observer.stop()
    }
}

import AppKit

/// The standard About panel, filled in. The app menu's own About item shows
/// only the icon, so its action is pointed here.
@MainActor
enum AboutPanel {
    static let copyright = "© 2026 Mohab. MIT License."
    private static let repoLine = "github.com/MMSs/usage-tracker"
    private static let repoURL = URL(string: "https://github.com/MMSs/usage-tracker")!

    static func options(build: BuildInfo) -> [NSApplication.AboutPanelOptionKey: Any] {
        [
            .applicationName: UsageTrackerApp.applicationName,
            .applicationVersion: build.version ?? "dev",
            .version: "",
            .credits: credits(),
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): copyright,
        ]
    }

    static func credits() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        func attributes(_ color: NSColor, link: URL? = nil) -> [NSAttributedString.Key: Any] {
            var result: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
            ]
            if let link { result[.link] = link }
            return result
        }

        let credits = NSMutableAttributedString()
        credits.append(NSAttributedString(string: repoLine + "\n", attributes: attributes(.labelColor, link: repoURL)))
        credits.append(NSAttributedString(
            string: "Not affiliated with Cursor, Anthropic or OpenAI.",
            attributes: attributes(.secondaryLabelColor)
        ))
        return credits
    }

    static func show(build: BuildInfo = .main) {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: options(build: build))
    }

    /// Target for the app menu's About item.
    final class Responder: NSObject {
        @objc func showAbout(_ sender: Any?) {
            MainActor.assumeIsolated { AboutPanel.show() }
        }
    }

    private static let responder = Responder()

    /// Points the app menu's standard About item at the filled-in panel. The
    /// menu is built by SwiftUI/AppKit, so this runs again whenever the app
    /// becomes active; it is idempotent.
    static func replaceAboutItem(in mainMenu: NSMenu?) {
        let standard = #selector(NSApplication.orderFrontStandardAboutPanel(_:))
        for host in mainMenu?.items ?? [] {
            for item in host.submenu?.items ?? [] where item.action == standard {
                item.target = responder
                item.action = #selector(Responder.showAbout(_:))
            }
        }
    }

    /// Retargets the About item each time a menu starts tracking, so a menu
    /// rebuilt after launch (activation policy changes, Settings opening) is
    /// fixed before the user sees it.
    @MainActor
    final class MenuTrackingObserver {
        private var token: NSObjectProtocol?
        private let center: NotificationCenter

        init(center: NotificationCenter = .default, mainMenu: @escaping @MainActor @Sendable () -> NSMenu?) {
            self.center = center
            token = center.addObserver(
                forName: NSMenu.didBeginTrackingNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    AboutPanel.replaceAboutItem(in: mainMenu())
                }
            }
        }

        func stop() {
            if let token { center.removeObserver(token) }
            token = nil
        }
    }
}

import SwiftUI

/// Which titled section of a settings page is open. Exactly one is, and a page
/// with a single titled section keeps it open.
struct SettingsAccordion: Equatable {
    let titles: [String]
    /// The one open section; nil when all are collapsed, which is how several start.
    private(set) var open: String?

    /// `open` is ignored when it names none of the titles. A lone section is always open.
    init(titles: [String], open: String? = nil) {
        self.titles = titles
        self.open = titles.count == 1 ? titles.first : open.flatMap { titles.contains($0) ? $0 : nil }
    }

    var isCollapsible: Bool { titles.count > 1 }

    func isOpen(_ title: String) -> Bool {
        title == open
    }

    /// Opens `title`, closing the one that was open. Unknown titles change nothing.
    mutating func open(_ title: String) {
        if titles.contains(title) {
            open = title
        }
    }

    /// What a disclosure control asks for: expanding opens `title`; collapsing
    /// the open section leaves every section collapsed, so the headings alone show.
    mutating func setExpanded(_ expanded: Bool, _ title: String) {
        if expanded {
            open(title)
        } else if isCollapsible, isOpen(title) {
            open = nil
        }
    }
}

private struct SettingsAccordionKey: EnvironmentKey {
    static let defaultValue: Binding<SettingsAccordion>? = nil
}

extension EnvironmentValues {
    /// The accordion the titled sections below belong to; nil leaves them always open.
    var settingsAccordion: Binding<SettingsAccordion>? {
        get { self[SettingsAccordionKey.self] }
        set { self[SettingsAccordionKey.self] = newValue }
    }
}

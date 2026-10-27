import SwiftUI

/// Which titled section of a settings page is open. Exactly one is, and a page
/// with a single titled section keeps it open.
struct SettingsAccordion: Equatable {
    let titles: [String]
    private(set) var open: String

    /// `open` falls back to the first title when it names none of them.
    init(titles: [String], open: String? = nil) {
        self.titles = titles
        self.open = open.flatMap { titles.contains($0) ? $0 : nil } ?? titles.first ?? ""
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

    /// What a disclosure control asks for: expanding opens `title`; collapsing is
    /// refused, since one section always stays open.
    mutating func setExpanded(_ expanded: Bool, _ title: String) {
        if expanded {
            open(title)
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

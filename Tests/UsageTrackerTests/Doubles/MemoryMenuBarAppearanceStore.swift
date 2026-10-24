@testable import UsageTracker

final class MemoryMenuBarAppearanceStore: MenuBarAppearanceStoring {
    private(set) var stored: MenuBarAppearance

    init(_ stored: MenuBarAppearance = .default) {
        self.stored = stored
    }

    func appearance() -> MenuBarAppearance {
        stored
    }

    func setAppearance(_ appearance: MenuBarAppearance) {
        stored = appearance
    }
}

import Foundation

enum MenuBarGraphStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case rings, bars

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rings: "Rings"
        case .bars: "Bars"
        }
    }
}

struct MenuBarAppearance: Equatable, Codable, Sendable {
    var showText = true
    var countdown = false
    var showGraph = true
    var graphStyle = MenuBarGraphStyle.rings
    var colored = false

    static let `default` = MenuBarAppearance()

    var drawsText: Bool { showText }
    var drawsGraph: Bool { showGraph }
    var drawsCountdown: Bool { countdown }

    /// Each switch is ignored when it would leave the item with no text,
    /// countdown or graph.
    func showingText(_ shows: Bool) -> MenuBarAppearance {
        guard shows || countdown || showGraph else {
            return self
        }

        var copy = self
        copy.showText = shows
        return copy
    }

    func showingCountdown(_ shows: Bool) -> MenuBarAppearance {
        guard shows || showText || showGraph else {
            return self
        }

        var copy = self
        copy.countdown = shows
        return copy
    }

    func showingGraph(_ shows: Bool) -> MenuBarAppearance {
        guard shows || showText || countdown else {
            return self
        }

        var copy = self
        copy.showGraph = shows
        return copy
    }
}

import Foundation

enum MenuBarGraphStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case rings, bars, battery, columns

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rings: "Rings"
        case .bars: "Bars"
        case .battery: "Battery"
        case .columns: "Columns"
        }
    }
}

enum MenuBarLimits: String, CaseIterable, Identifiable, Codable, Sendable {
    case both, short, long

    var id: String { rawValue }

    /// The provider's window names, or Short and Long when there is no one provider.
    func title(names: MeterNames?) -> String {
        switch self {
        case .both: "Both"
        case .short: names?.short ?? "Short"
        case .long: names?.long ?? "Long"
        }
    }
}

struct MenuBarAppearance: Equatable, Codable, Sendable {
    var showText = true
    var countdown = false
    var showGraph = true
    var graphStyle = MenuBarGraphStyle.rings
    var colored = false
    var showPlanUsage = true
    var showAPISpend = true
    var limits = MenuBarLimits.both

    static let `default` = MenuBarAppearance()

    var drawsText: Bool { showText }
    var drawsGraph: Bool { showGraph }
    var drawsCountdown: Bool { countdown }

    /// The API spend amount follows Show text, but stays when nothing else
    /// would mark the spend: no graph drawn, or no budget to draw it against.
    func showsSpendAmount(hasMeter: Bool) -> Bool {
        showText || !(showGraph && hasMeter)
    }

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

    /// The two halves follow the same rule: one stays visible.
    func showingPlanUsage(_ shows: Bool) -> MenuBarAppearance {
        guard shows || showAPISpend else {
            return self
        }

        var copy = self
        copy.showPlanUsage = shows
        return copy
    }

    func showingAPISpend(_ shows: Bool) -> MenuBarAppearance {
        guard shows || showPlanUsage else {
            return self
        }

        var copy = self
        copy.showAPISpend = shows
        return copy
    }
}

/// Decoding is tolerant so an override saved by an older build keeps its
/// values: a missing key takes its default, an unknown raw value its fallback.
extension MenuBarAppearance {
    private enum CodingKeys: String, CodingKey {
        case showText, countdown, showGraph, graphStyle, colored, showPlanUsage, showAPISpend, limits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = MenuBarAppearance()

        self.init(
            showText: try container.decodeIfPresent(Bool.self, forKey: .showText) ?? fallback.showText,
            countdown: try container.decodeIfPresent(Bool.self, forKey: .countdown) ?? fallback.countdown,
            showGraph: try container.decodeIfPresent(Bool.self, forKey: .showGraph) ?? fallback.showGraph,
            graphStyle: try container.decodeIfPresent(String.self, forKey: .graphStyle)
                .flatMap(MenuBarGraphStyle.init(rawValue:)) ?? fallback.graphStyle,
            colored: try container.decodeIfPresent(Bool.self, forKey: .colored) ?? fallback.colored,
            showPlanUsage: try container.decodeIfPresent(Bool.self, forKey: .showPlanUsage) ?? fallback.showPlanUsage,
            showAPISpend: try container.decodeIfPresent(Bool.self, forKey: .showAPISpend) ?? fallback.showAPISpend,
            limits: try container.decodeIfPresent(String.self, forKey: .limits)
                .flatMap(MenuBarLimits.init(rawValue:)) ?? fallback.limits
        )
    }
}

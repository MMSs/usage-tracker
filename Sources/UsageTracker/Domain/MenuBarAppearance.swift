import Foundation

enum MenuBarGraphStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case rings, bars, battery, gauge, segments, columns, dials

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rings: "Rings"
        case .bars: "Bars"
        case .battery: "Battery"
        case .gauge: "Gauge"
        case .segments: "Segments"
        case .columns: "Columns"
        case .dials: "Dials"
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
    var limits = MenuBarLimits.both

    static let `default` = MenuBarAppearance()

    var drawsText: Bool { showText }
    var drawsGraph: Bool { showGraph }
    var drawsCountdown: Bool { countdown }

    /// The API spend amount follows Show text, and also marks the spend when
    /// the graph is on but there is no budget to draw it against.
    func showsSpendAmount(hasMeter: Bool) -> Bool {
        showText || (showGraph && !hasMeter)
    }
}

/// Decoding is tolerant so an override saved by an older build keeps its
/// values: a missing key takes its default, an unknown raw value its fallback.
extension MenuBarAppearance {
    private enum CodingKeys: String, CodingKey {
        case showText, countdown, showGraph, graphStyle, colored, limits
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
            limits: try container.decodeIfPresent(String.self, forKey: .limits)
                .flatMap(MenuBarLimits.init(rawValue:)) ?? fallback.limits
        )
    }
}

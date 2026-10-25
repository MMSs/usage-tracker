import CoreGraphics
import Foundation

/// What each graph style occupies in the menu bar item. The views frame
/// themselves from `size`, so the item's width is whatever this reports.
/// A new style adds a `MenuBarGraphStyle` case, a case in `size`, and any
/// pure rules it needs as static functions here.
enum MenuBarGraphGeometry {
    static let ringDiameter: CGFloat = 18
    static let barsWidth: CGFloat = 28
    static let barHeight: CGFloat = 3.5
    static let barSpacing: CGFloat = 3

    static let batterySize = CGSize(width: 44, height: 14)
    static let batteryBodyWidth: CGFloat = 42
    static let batteryInset: CGFloat = 2
    static let batteryNubSize = CGSize(width: 2, height: 6)
    static let segmentCount = 10
    static let segmentSize = CGSize(width: 3.4, height: 6)
    static let segmentSpacing: CGFloat = 0.9
    static let segmentRowSpacing: CGFloat = 2
    static let columnWidth: CGFloat = 4.5
    static let columnHeight: CGFloat = 16
    static let columnSpacing: CGFloat = 5

    static let gaugeSize = CGSize(width: 24, height: 14)
    static let gaugeStroke: CGFloat = 2.5
    /// The outer arc's outer edge, measured from the arc's centre.
    static let gaugeOuterRadius: CGFloat = 12
    static let gaugeArcSpacing: CGFloat = 4
    static let pieDiameter: CGFloat = 18
    static let pieInnerWedgeRadius: CGFloat = 4.5
    static let pieBandInnerRadius: CGFloat = 6
    static let sparklineSize = CGSize(width: 40, height: 16)
    static let sparklineSpan: TimeInterval = 12 * 3600
    static let dialDiameter: CGFloat = 16
    static let dialSpacing: CGFloat = 3

    /// The battery shows what remains, so it fills as the meter empties.
    static func batteryFill(_ fraction: Double?) -> Double? {
        fraction.map { 1 - $0 }
    }

    /// One block per tenth started, so any use at all lights the first.
    /// The tolerance keeps 0.3 (3.0000000000000004 once scaled) at three.
    static func litSegments(_ fraction: Double?) -> Int {
        guard let fraction, fraction.isFinite else { return 0 }
        return min(max(Int((fraction * Double(segmentCount) - 1e-9).rounded(.up)), 0), segmentCount)
    }

    /// The sparkline's polyline, left to right: the last twelve hours of
    /// `samples`, one point per whole-point column (the latest in it, so a
    /// reset still drops to its low), ending at the live value, which counts
    /// as the latest point of its own column. No samples yet draws only that
    /// end; no history source at all (`nil`) draws a flat line at `current`.
    static func sparklinePoints(samples: [UsageSample]?, current: Double?, now: Date, size: CGSize) -> [CGPoint] {
        guard let current, current.isFinite else { return [] }

        func y(_ percent: Double) -> CGFloat {
            size.height * (1 - CGFloat(min(max(percent, 0), 100) / 100))
        }

        let end = CGPoint(x: size.width, y: y(current * 100))

        guard let samples else {
            return [CGPoint(x: 0, y: end.y), end]
        }

        var latest: [Int: (date: Date, point: CGPoint)] = [:]

        for sample in samples {
            let age = now.timeIntervalSince(sample.date)
            guard age >= 0, age < sparklineSpan else { continue }

            let x = size.width * CGFloat(1 - age / sparklineSpan)
            let column = Int(x.rounded(.down))

            if let kept = latest[column], kept.date > sample.date { continue }
            latest[column] = (sample.date, CGPoint(x: x, y: y(Double(sample.percent))))
        }

        latest[Int(size.width.rounded(.down))] = nil

        var points: [CGPoint] = []
        for column in latest.keys.sorted() {
            if let kept = latest[column] { points.append(kept.point) }
        }
        points.append(end)

        return points
    }

    static func size(_ style: MenuBarGraphStyle, meterCount: Int) -> CGSize {
        switch style {
        case .rings:
            return CGSize(width: ringDiameter, height: ringDiameter)
        case .bars:
            let count = CGFloat(max(meterCount, 0))
            return CGSize(
                width: barsWidth,
                height: barHeight * count + barSpacing * max(count - 1, 0)
            )
        case .battery:
            return batterySize
        case .gauge:
            return gaugeSize
        case .segments:
            let rows = CGFloat(min(max(meterCount, 0), 2))
            return CGSize(
                width: segmentSize.width * CGFloat(segmentCount) + segmentSpacing * CGFloat(segmentCount - 1),
                height: segmentSize.height * rows + segmentRowSpacing * max(rows - 1, 0)
            )
        case .pie:
            return CGSize(width: pieDiameter, height: pieDiameter)
        case .sparkline:
            return sparklineSize
        case .dials:
            let count = CGFloat(max(meterCount, 0))
            return CGSize(
                width: dialDiameter * count + dialSpacing * max(count - 1, 0),
                height: dialDiameter
            )
        case .columns:
            let count = CGFloat(max(meterCount, 0))
            return CGSize(
                width: columnWidth * count + columnSpacing * max(count - 1, 0),
                height: columnHeight
            )
        }
    }
}

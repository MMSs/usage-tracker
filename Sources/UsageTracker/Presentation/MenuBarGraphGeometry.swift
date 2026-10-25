import CoreGraphics

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
    static let columnWidth: CGFloat = 4.5
    static let columnHeight: CGFloat = 16
    static let columnSpacing: CGFloat = 5

    /// The battery shows what remains, so it fills as the meter empties.
    static func batteryFill(_ fraction: Double?) -> Double? {
        fraction.map { 1 - $0 }
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
        case .columns:
            let count = CGFloat(max(meterCount, 0))
            return CGSize(
                width: columnWidth * count + columnSpacing * max(count - 1, 0),
                height: columnHeight
            )
        }
    }
}

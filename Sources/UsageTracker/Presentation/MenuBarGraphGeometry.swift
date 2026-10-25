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
        }
    }
}

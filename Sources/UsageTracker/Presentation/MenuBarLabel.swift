import SwiftUI

/// The menu bar item. Drawn as one image (see `MenuBarItemImage`); the
/// colour scheme here follows the menu bar, which picks the foreground for
/// coloured images.
struct MenuBarLabel: View {
    let item: MenuBarItem
    let appearance: MenuBarAppearance
    let displayName: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let image = MenuBarItemImage.render(
            item,
            appearance: appearance,
            displayName: displayName,
            darkMenuBar: colorScheme == .dark
        ) {
            Image(nsImage: image)
                .accessibilityLabel(item.accessibilityText(displayName: displayName))
        } else {
            Text(item.accessibilityText(displayName: displayName))
        }
    }
}

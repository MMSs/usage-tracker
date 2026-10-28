import SwiftUI

/// The menu bar item. Drawn as one image (see `MenuBarItemImage`); the
/// colour scheme here follows the menu bar, which picks the foreground for
/// coloured images.
struct MenuBarLabel: View {
    let item: MenuBarItem
    let appearance: MenuBarAppearance
    let halves: MenuBarHalves
    let displayName: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shown = item.visible(in: appearance, halves: halves)

        if let image = MenuBarItemImage.render(
            item,
            appearance: appearance,
            halves: halves,
            displayName: displayName,
            darkMenuBar: colorScheme == .dark
        ) {
            Image(nsImage: image)
                .accessibilityLabel(shown.accessibilityText(displayName: displayName))
        } else {
            Text(shown.accessibilityText(displayName: displayName))
        }
    }
}

/// The app's own item while no provider is set up, so the first thing a new
/// user sees names no provider.
struct SetUpMenuBarLabel: View {
    let appName: String

    var body: some View {
        if let image = MenuBarItemImage.renderSetUp(appName: appName) {
            Image(nsImage: image)
                .accessibilityLabel("\(appName), Set up")
        } else {
            Text("Set up")
        }
    }
}

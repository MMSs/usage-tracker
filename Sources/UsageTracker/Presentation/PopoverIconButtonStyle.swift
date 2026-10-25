import SwiftUI

/// The popover's icon buttons: a 22pt hit target with a rounded highlight on
/// hover and a stronger one, slightly shrunk, while pressed.
struct PopoverIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration)
    }

    private struct Content: View {
        let configuration: ButtonStyle.Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.primary.opacity(configuration.isPressed ? 0.16 : hovering ? 0.08 : 0))
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .onHover { hovering = $0 }
        }
    }
}

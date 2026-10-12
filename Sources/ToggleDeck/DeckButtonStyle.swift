import SwiftUI

/// SwiftUI-drawn buttons stay legible in light/dark mode and render previews.
struct DeckButtonStyle: ButtonStyle {
  @ViewState<Bool> private var hovered = false
  @Environment(\.isEnabled) private var enabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .contentShape(RoundedRectangle(cornerRadius: 5))
      .background(
        enabled && (hovered || configuration.isPressed) ? Color.primary.opacity(0.08) : .clear,
        in: RoundedRectangle(cornerRadius: 5)
      )
      .opacity(enabled ? 1 : 0.5)
      .onHover { hovered = $0 }
  }
}

struct DeckRowButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View { configuration.label }
}

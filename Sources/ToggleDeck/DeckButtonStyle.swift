import SwiftUI

/// SwiftUI-drawn buttons stay legible in light/dark mode and render previews.
/// Row buttons use `DeckRowButtonStyle` in DeckStyle.swift.
struct DeckButtonStyle: ButtonStyle {
  @ViewState<Bool> private var hovered = false
  @Environment(\.isEnabled) private var enabled

  func makeBody(configuration: Configuration) -> some View {
    let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
    configuration.label
      .contentShape(shape)
      .background(
        enabled && configuration.isPressed
          ? DeckStyle.pressedFill : (enabled && hovered ? DeckStyle.hoverFill : .clear),
        in: shape
      )
      .opacity(enabled ? 1 : 0.5)
      .onHover { hovered = $0 }
  }
}

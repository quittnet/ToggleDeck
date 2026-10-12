import SwiftUI

/// One keyboard-accessible button covers the entire row; the switch is its state indicator.
@MainActor
struct DropdownControlRow: View {
  let spec: ToggleSpec
  let state: ToggleState
  let showDescriptions: Bool
  let isFocused: Bool
  var snapshot = false
  let onToggle: () -> Void
  @ViewState<Bool> private var hovered = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var disabled: Bool { !state.supported || state.stale || state.busy }

  private var subtitle: String? {
    if state.stale { return "Reading current state…" }
    if state.error != nil { return "Could not apply · right-click to refresh" }
    if !state.supported { return "Unavailable · refresh or check System Settings" }
    return spec.menuSubtitle(showDescriptions: showDescriptions)
  }

  var body: some View {
    Button(action: onToggle) {
      HStack(spacing: 10) {
        Image(systemName: spec.menuSymbol)
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(state.isOn && !disabled ? Color.accentColor : Color.secondary)
          .frame(width: 22)
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 2) {
          Text(spec.menuTitle)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(state.supported ? .primary : .secondary)
            .lineLimit(1)
          if let subtitle {
            Text(subtitle)
              .font(.system(size: 11))
              .foregroundStyle(.secondary)
              .lineLimit(showDescriptions ? 2 : 1)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if state.stale || state.busy {
          if snapshot {
            Circle().trim(from: 0.1, to: 0.85).stroke(Color.secondary, lineWidth: 1.5)
              .frame(width: 14, height: 14).frame(width: 38, height: 22).accessibilityHidden(true)
          } else {
            ProgressView().controlSize(.small).frame(width: 38, height: 22)
          }
        } else if !state.supported {
          Image(systemName: "minus.circle")
            .foregroundStyle(.secondary).frame(width: 38, height: 22)
        } else {
          SwitchIndicator(isOn: state.isOn)
            .opacity(state.stale ? 0.4 : 1)
        }
      }
      .padding(.horizontal, 10)
      .frame(height: spec.menuHeight(showDescriptions: showDescriptions))
      .contentShape(RoundedRectangle(cornerRadius: 8))
      .background(
        hovered && !disabled ? Color.primary.opacity(0.055) : .clear,
        in: RoundedRectangle(cornerRadius: 8)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .strokeBorder(isFocused ? Color.accentColor : .clear, lineWidth: 2)
      }
      .overlay(alignment: .trailing) {
        if state.error != nil {
          Image(systemName: "exclamationmark.circle.fill")
            .font(.system(size: 10)).foregroundStyle(.orange)
            .offset(x: 2, y: -12).accessibilityHidden(true)
        }
      }
    }
    .buttonStyle(DeckRowButtonStyle())
    .focusable(!disabled)
    .focusEffectDisabled()
    .onKeyPress(.space) {
      guard !disabled else { return .ignored }
      onToggle()
      return .handled
    }
    .disabled(disabled)
    .onHover { hovered = $0 }
    .help(state.error ?? (!state.supported ? "Not available on this Mac." : spec.menuHelp))
    .accessibilityLabel(spec.menuTitle)
    .accessibilityValue(
      state.stale
        ? "Reading"
        : (state.busy
          ? "Applying" : (!state.supported ? "Unavailable" : (state.isOn ? "On" : "Off")))
    )
    .accessibilityHint(state.error ?? spec.menuHelp)
    .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: state.isOn)
  }
}

private struct SwitchIndicator: View {
  let isOn: Bool

  var body: some View {
    Capsule()
      .fill(isOn ? Color.accentColor : Color(nsColor: .tertiaryLabelColor))
      .frame(width: 38, height: 22)
      .overlay(alignment: isOn ? .trailing : .leading) {
        Circle().fill(.white).frame(width: 18, height: 18).padding(2)
      }
      .accessibilityHidden(true)
  }
}

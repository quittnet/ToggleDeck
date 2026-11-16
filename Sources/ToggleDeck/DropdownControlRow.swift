import SwiftUI

/// One keyboard-accessible button covers the entire row; the switch is its state indicator.
@MainActor
struct DropdownControlRow: View {
  let spec: ToggleSpec
  let state: ToggleState
  let showDescriptions: Bool
  let isFocused: Bool
  var snapshot = false
  /// Space kept clear at the trailing edge for a button the dropdown lays
  /// over the row, such as the pin shown while browsing.
  var trailingReserve: CGFloat = 0
  let onToggle: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Busy rows stay enabled so they keep keyboard focus through a write;
  /// the engine already ignores a second write while one is in flight.
  private var disabled: Bool { !DropdownNavigation.isNavigable(state) }

  private var subtitle: String? {
    if state.stale { return "Reading current state…" }
    if state.error != nil { return "Could not apply · right-click to refresh" }
    if !state.supported { return "Unavailable · refresh or check System Settings" }
    return spec.menuSubtitle(showDescriptions: showDescriptions)
  }

  var body: some View {
    Button(action: onToggle) {
      HStack(spacing: DeckStyle.rowSpacing) {
        IconTile(
          symbol: spec.menuSymbol(isOn: state.isOn), tint: spec.category.tint,
          isLit: state.isOn && !disabled, isDimmed: !state.supported)

        VStack(alignment: .leading, spacing: 1) {
          Text(spec.menuTitle)
            .font(DeckStyle.rowTitle)
            .foregroundStyle(state.supported ? .primary : .secondary)
            .lineLimit(1)
          if let subtitle {
            Text(subtitle)
              .font(DeckStyle.rowSubtitle)
              .foregroundStyle(.secondary)
              .lineLimit(showDescriptions ? 2 : 1)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        trailing
      }
      .padding(.leading, DeckStyle.rowInset)
      .padding(.trailing, DeckStyle.rowInset + trailingReserve)
      .frame(height: spec.menuHeight(showDescriptions: showDescriptions))
      .contentShape(Rectangle())
    }
    // No highlight mid-write: a click then does nothing, and the spinner
    // beside the switch already says why.
    .buttonStyle(DeckRowButtonStyle(isFocused: isFocused, highlights: !state.busy))
    .focusable(!disabled)
    .focusEffectDisabled()
    .onKeyPress(.space) {
      guard !disabled else { return .ignored }
      onToggle()
      return .handled
    }
    .disabled(disabled)
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

  @ViewBuilder
  private var trailing: some View {
    if state.stale {
      DeckSpinner(snapshot: snapshot)
        .frame(width: DeckStyle.switchSize.width, height: DeckStyle.switchSize.height)
    } else if !state.supported {
      Image(systemName: "minus.circle")
        .font(.system(size: 13)).foregroundStyle(.tertiary)
        .frame(width: DeckStyle.switchSize.width, height: DeckStyle.switchSize.height)
        .accessibilityHidden(true)
    } else {
      HStack(spacing: 6) {
        if state.error != nil {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 11)).foregroundStyle(DeckStyle.warning)
            .accessibilityHidden(true)
        }
        if state.busy { DeckSpinner(snapshot: snapshot) }
        DeckSwitch(isOn: state.isOn, tint: spec.category.tint)
      }
    }
  }
}

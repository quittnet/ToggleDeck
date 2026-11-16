import SwiftUI

/// One switch, shared by the dropdown and the settings window.
@MainActor
struct ToggleRow: View {
  let spec: ToggleSpec
  @ObservedObject var engine: ToggleEngine
  @ObservedObject var settings: AppSettings

  var showPin = false
  var showDetail = true
  var showCategory = false
  var showMove = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var st: ToggleState { engine.state(spec.id) }
  private var isPinned: Bool { settings.isPinned(spec.id) }

  var body: some View {
    HStack(alignment: .center, spacing: DeckStyle.rowSpacing) {
      IconTile(
        symbol: spec.menuSymbol(isOn: st.isOn), tint: spec.category.tint,
        isLit: st.isOn && st.supported && !st.stale)

      VStack(alignment: .leading, spacing: 2) {
        titleLine
        if showCategory {
          Text(spec.category.rawValue)
            .font(DeckStyle.rowSubtitle)
            .foregroundStyle(.secondary)
        }
        if showDetail, !spec.detail.isEmpty {
          Text(spec.detail)
            .font(DeckStyle.rowSubtitle)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        }
        if let error = st.error {
          Text(error)
            .font(DeckStyle.rowSubtitle)
            .foregroundStyle(DeckStyle.warning)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      Spacer(minLength: 8)

      if showMove { moveButtons }
      if showPin { pinButton }
      trailingSwitch
    }
    .padding(.horizontal, DeckStyle.rowInset)
    .padding(.vertical, showDetail ? 9 : 7)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .opacity(st.stale ? 0.55 : 1)
    .accessibilityElement(children: .contain)
    .contextMenu { ControlContextMenu(spec: spec, engine: engine, settings: settings) }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: st.isOn)
  }

  private var titleLine: some View {
    HStack(spacing: 5) {
      Text(spec.menuTitle)
        .font(DeckStyle.rowTitle)
        .foregroundStyle(st.supported ? .primary : .secondary)
        .lineLimit(1)

      if !st.supported {
        Text("unavailable")
          .font(.system(size: 9.5, weight: .medium))
          .padding(.horizontal, 5).padding(.vertical, 1)
          .background(DeckStyle.quietFill, in: Capsule())
          .foregroundStyle(.secondary)
      }

      ForEach(spec.requires.badges, id: \.0) { badge in
        Image(systemName: badge.1)
          .font(.system(size: 9))
          .foregroundStyle(.tertiary)
          .help(badge.0)
      }
    }
  }

  private var pinButton: some View {
    Button {
      settings.togglePin(spec.id)
    } label: {
      Image(systemName: isPinned ? "pin.fill" : "pin")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(isPinned ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
        .frame(width: 26, height: 26)
    }
    .buttonStyle(DeckButtonStyle())
    .accessibilityLabel(isPinned ? "Unpin \(spec.title)" : "Pin \(spec.title)")
    .help(isPinned ? "Remove from the menu bar dropdown" : "Add to the menu bar dropdown")
  }

  private var moveButtons: some View {
    HStack(spacing: 0) {
      Button {
        settings.movePin(spec.id, by: -1)
      } label: {
        Image(systemName: "chevron.up").frame(width: 24, height: 24)
      }
      .disabled(settings.pinned.first == spec.id)
      .accessibilityLabel("Move \(spec.menuTitle) up")
      Button {
        settings.movePin(spec.id, by: 1)
      } label: {
        Image(systemName: "chevron.down").frame(width: 24, height: 24)
      }
      .disabled(settings.pinned.last == spec.id)
      .accessibilityLabel("Move \(spec.menuTitle) down")
    }
    .buttonStyle(DeckButtonStyle())
    .font(.system(size: 10, weight: .semibold))
    .foregroundStyle(.secondary)
  }

  @ViewBuilder
  private var trailingSwitch: some View {
    if st.stale {
      ProgressView()
        .controlSize(.small)
        .scaleEffect(0.7)
        .frame(width: DeckStyle.switchSize.width)
    } else {
      HStack(spacing: 6) {
        if st.busy {
          ProgressView()
            .controlSize(.small)
            .scaleEffect(0.7)
        }
        Toggle(
          spec.title,
          isOn: Binding(
            get: { st.isOn },
            set: { newValue in
              Task { await engine.set(spec.id, on: newValue) }
            }
          )
        )
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
        .tint(spec.category.tint)
        .disabled(!st.supported || st.stale || st.busy)
        .accessibilityHint(spec.detail)
      }
    }
  }
}

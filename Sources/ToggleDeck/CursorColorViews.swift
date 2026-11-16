import AppKit
import SwiftUI

struct CursorArrowShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    for (index, point) in [
      CGPoint(x: 0.14, y: 0.04), CGPoint(x: 0.14, y: 0.84),
      CGPoint(x: 0.34, y: 0.65), CGPoint(x: 0.5, y: 0.96),
      CGPoint(x: 0.66, y: 0.87), CGPoint(x: 0.5, y: 0.57),
      CGPoint(x: 0.83, y: 0.57),
    ].enumerated() {
      let scaled = CGPoint(
        x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
      if index == 0 { path.move(to: scaled) } else { path.addLine(to: scaled) }
    }
    path.closeSubpath()
    return path
  }
}

struct CursorArrowPreview: View {
  let colors: CursorColors
  var body: some View {
    CursorArrowShape().fill(Color(nsColor: colors.fill.nsColor))
      .overlay {
        CursorArrowShape().stroke(
          Color(nsColor: colors.outline.nsColor),
          style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
      }.accessibilityHidden(true)
  }
}

/// The arrow on a neutral tile. The fill sits between white and black in both
/// appearances, so a black and a white pointer both stay visible on it.
struct CursorArrowTile: View {
  let colors: CursorColors
  var size: CGFloat = DeckStyle.tileSize

  var body: some View {
    RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
      .fill(DeckStyle.quietFill)
      .frame(width: size, height: size)
      .overlay {
        // The arrow's mass sits left of its box; nudge it to look centered.
        CursorArrowPreview(colors: colors)
          .frame(width: size * 0.5, height: size * 0.66)
          .offset(x: size * 0.03)
      }
      .accessibilityHidden(true)
  }
}

@MainActor
struct CursorColorMenu: View {
  @ObservedObject var cursor: CursorColorController
  @ObservedObject var pointer: PointerController = .shared
  var onCustom: () -> Void
  var snapshot = false
  /// Set by the dropdown while keyboard focus is on this row.
  var isFocused = false
  @ViewState<Bool> private var showing = false

  private var error: String? { cursor.error ?? pointer.error }

  private var status: String {
    if cursor.isLoading { return "Reading…" }
    if cursor.isApplying { return "Applying…" }
    if !cursor.available { return "Unavailable" }
    return cursor.selectionName
  }

  var body: some View {
    Group {
      if snapshot {
        label
      } else {
        Button {
          showing.toggle()
        } label: {
          label
        }
        .buttonStyle(DeckRowButtonStyle(isFocused: isFocused))
        // A plain button takes key focus only with Full Keyboard Access on,
        // and the dropdown's arrow keys have to land here without it.
        .focusable(!cursor.isApplying)
        .focusEffectDisabled()
        .onKeyPress(.space) {
          guard !cursor.isApplying else { return .ignored }
          showing.toggle()
          return .handled
        }
        .disabled(cursor.isApplying)
        .popover(isPresented: $showing, arrowEdge: .trailing) {
          CursorColorPicker(
            cursor: cursor, pointer: pointer,
            onCustom: {
              showing = false
              onCustom()
            })
        }
      }
    }
    .frame(
      height: error == nil
        ? DropdownLayout.cursorRowHeight : DropdownLayout.cursorAttentionRowHeight,
      alignment: .center
    )
    .accessibilityLabel("Cursor Color: \(status)")
    .accessibilityHint(error ?? "Choose colors, adjust pointer size, or enable shake to locate.")
    .help(error ?? "Change your Mac's pointer color, size, and shake to locate")
  }

  private var label: some View {
    DeckValueRowLabel(
      title: "Cursor Color",
      subtitle: error == nil ? nil : "Needs attention · details inside",
      value: status, isBusy: cursor.isApplying, snapshot: snapshot
    ) {
      CursorArrowTile(colors: cursor.colors)
    }
  }

  static func openPointerSettings() {
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_Display")
    {
      NSWorkspace.shared.open(url)
    }
  }

  static func openFullDiskAccess() {
    if let url = URL(
      string:
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")
    {
      NSWorkspace.shared.open(url)
    }
  }
}

/// Contents of the cursor row's popover: colors, pointer size, shake to
/// locate, and the less frequent actions.
@MainActor
struct CursorColorPicker: View {
  @ObservedObject var cursor: CursorColorController
  @ObservedObject var pointer: PointerController
  var onCustom: () -> Void = {}

  static let width: CGFloat = 320

  private var error: String? { cursor.error ?? pointer.error }
  private var pointerLocked: Bool {
    pointer.isLoading || pointer.isApplying || !pointer.available
  }
  private var cursorLocked: Bool { cursor.isLoading || cursor.isApplying || !cursor.available }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let error {
        DeckNotice(message: error) {
          Button("Full Disk Access…") { CursorColorMenu.openFullDiskAccess() }
        }
        DeckSeparator(leadingInset: 0)
      }

      CursorSwatchGrid(cursor: cursor)

      DeckSeparator(leadingInset: 0)

      VStack(alignment: .leading, spacing: 6) {
        DeckSectionLabel(title: "Pointer Size")
        PointerSizeChips(current: pointer.available ? pointer.settings.scale : nil) { scale in
          Task {
            await pointer.apply(
              PointerSettings(scale: scale, shakeToFind: pointer.settings.shakeToFind))
          }
        }
        .disabled(pointerLocked)
      }

      HStack {
        Text("Shake to Find Pointer").font(DeckStyle.rowTitle).accessibilityHidden(true)
        Spacer(minLength: 8)
        Toggle(
          "Shake to Find Pointer",
          isOn: Binding(
            get: { pointer.settings.shakeToFind },
            set: { enabled in
              Task {
                await pointer.apply(
                  PointerSettings(scale: pointer.settings.scale, shakeToFind: enabled))
              }
            })
        )
        .toggleStyle(.switch).controlSize(.small).labelsHidden()
      }
      .disabled(pointerLocked)

      DeckSeparator(leadingInset: 0)

      VStack(alignment: .leading, spacing: 0) {
        Button("Save Current Combination") { cursor.palettes.save(cursor.colors) }
          .disabled(cursorLocked || cursor.palettes.matching(cursor.colors) != nil)
        Button("Custom Colors…", action: onCustom)
        Button("Refresh Cursor Settings") {
          Task {
            await cursor.refresh()
            await pointer.refresh()
          }
        }
        .disabled(
          cursor.isRefreshing || cursor.isApplying || pointer.isRefreshing
            || pointer.isApplying)
        Button("Open Pointer Settings…") { CursorColorMenu.openPointerSettings() }
      }
      .buttonStyle(DeckActionButtonStyle())
      // Lets the action titles line up with the content while their
      // highlight still spans a comfortable target.
      .padding(.horizontal, -DeckActionButtonStyle.textInset)
    }
    .padding(14)
    .frame(width: Self.width)
  }
}

/// Every color choice for the pointer as chips: solid presets, combinations,
/// then saved combinations.
@MainActor
struct CursorSwatchGrid: View {
  @ObservedObject var cursor: CursorColorController
  var chipSize: CGFloat = 28
  var spacing: CGFloat = 4
  /// Receives the colors macOS reports after the change.
  var onChoose: (CursorColors) -> Void = { _ in }

  // Nine solid presets, so that group fills exactly one row.
  private static let columns = 9

  private struct Choice: Identifiable {
    let id: String
    let name: String
    let colors: CursorColors
  }

  private var locked: Bool { cursor.isLoading || cursor.isApplying || !cursor.available }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      group(
        "Solid Colors",
        CursorPreset.solidPresets.map {
          Choice(id: "p-\($0.id)", name: $0.rawValue, colors: $0.colors)
        })
      group(
        "Combinations",
        CursorPreset.combinationPresets.map {
          Choice(id: "p-\($0.id)", name: $0.rawValue, colors: $0.colors)
        })
      if !cursor.palettes.savedColors.isEmpty {
        group(
          "Saved Combinations",
          cursor.palettes.savedColors.map {
            Choice(id: "s-\($0.id)", name: $0.name, colors: $0.colors)
          })
      }
    }
  }

  private func group(_ title: String, _ choices: [Choice]) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      DeckSectionLabel(title: title)
      LazyVGrid(
        columns: Array(
          repeating: GridItem(.fixed(chipSize), spacing: spacing), count: Self.columns),
        alignment: .leading, spacing: spacing
      ) {
        ForEach(choices) { swatch($0) }
      }
      .fixedSize()
    }
  }

  private func swatch(_ choice: Choice) -> some View {
    let selected =
      cursor.colors.matches(choice.colors)
      && cursor.colors.customized == choice.colors.customized
    let shape = RoundedRectangle(cornerRadius: chipSize * 0.27, style: .continuous)
    return Button {
      Task {
        await cursor.apply(choice.colors)
        onChoose(cursor.colors)
      }
    } label: {
      CursorArrowTile(colors: choice.colors, size: chipSize)
        .overlay {
          shape.strokeBorder(
            selected ? Color.accentColor : DeckStyle.cardStroke, lineWidth: selected ? 2 : 1)
        }
    }
    .buttonStyle(SwatchButtonStyle(shape: shape))
    .disabled(locked)
    .accessibilityLabel(choice.name)
    .accessibilityAddTraits(selected ? .isSelected : [])
    .help(choice.name)
  }
}

private struct SwatchButtonStyle: ButtonStyle {
  let shape: RoundedRectangle
  @ViewState<Bool> private var hovered = false
  @Environment(\.isEnabled) private var enabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .overlay {
        shape.fill(
          enabled && configuration.isPressed
            ? DeckStyle.pressedFill : (enabled && hovered ? DeckStyle.hoverFill : .clear))
      }
      .contentShape(shape)
      .opacity(enabled ? 1 : 0.45)
      .onHover { hovered = $0 }
  }
}

@MainActor
struct CursorColorsPane: View {
  @ObservedObject var cursor: CursorColorController
  @ObservedObject var pointer: PointerController = .shared
  @ViewState<CursorColors> private var draft = .standard
  @ViewState<String> private var name = ""
  @ViewState<String?> private var savedMessage = nil

  private let inset = DeckStyle.cardInset

  private var canApply: Bool {
    cursor.available && !cursor.isLoading && !cursor.isApplying && draft.isValid
      && (!draft.matches(cursor.colors) || draft.customized != cursor.colors.customized)
  }

  private var canSave: Bool {
    guard draft.isValid, !cursor.isLoading, !cursor.isApplying else { return false }
    guard let saved = cursor.palettes.matching(draft) else { return true }
    let requested = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return !requested.isEmpty && requested != saved.name
  }

  var body: some View {
    PaneScaffold {
      PaneHeader(
        title: "Cursor", subtitle: "Adjust your Mac’s pointer size, visibility, and colors."
      ) {
        Button {
          Task {
            await cursor.refresh()
            await pointer.refresh()
          }
        } label: {
          if cursor.isRefreshing || pointer.isRefreshing {
            ProgressView().controlSize(.small)
          } else {
            Image(systemName: "arrow.clockwise")
          }
        }
        .buttonStyle(.borderless)
        .disabled(
          cursor.isRefreshing || cursor.isApplying || pointer.isRefreshing
            || pointer.isApplying
        )
        .help("Refresh cursor settings").accessibilityLabel("Refresh cursor settings")
      }

      PaneSection(title: "Pointer") {
        PointerControlsView(pointer: pointer)
      }

      PaneSection(title: "Colors") {
        HStack(spacing: 0) {
          sample(background: .white, name: "Light background")
          sample(background: Color(white: 0.12), name: "Dark background")
        }
        .frame(height: 96)
        .clipShape(DeckStyle.row)
        .overlay { DeckStyle.row.strokeBorder(DeckStyle.cardStroke) }
        .padding(inset)

        DeckSeparator(leadingInset: inset)

        CursorSwatchGrid(cursor: cursor, chipSize: 34, spacing: 8, onChoose: { draft = $0 })
          .padding(inset)

        DeckSeparator(leadingInset: inset)

        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 28) {
            ColorPicker("Fill color", selection: colorBinding(fill: true), supportsOpacity: false)
              .accessibilityLabel("Cursor fill color")
            ColorPicker(
              "Outline color", selection: colorBinding(fill: false), supportsOpacity: false
            )
            .accessibilityLabel("Cursor outline color")
          }
          .font(DeckStyle.rowTitle)
          .disabled(cursor.isLoading || cursor.isApplying)

          TextField("Combination name (optional)", text: $name)
            .textFieldStyle(.roundedBorder).frame(maxWidth: 320)
            .accessibilityLabel("Saved combination name")

          HStack(spacing: 8) {
            Button(cursor.isApplying ? "Applying…" : "Save & Apply") {
              let requested = draft
              saveDraft()
              Task { await cursor.apply(requested) }
            }.buttonStyle(.borderedProminent).disabled(!canApply)
            Button("Save Combination", action: saveDraft).disabled(!canSave)
            Button("Reset to Default") {
              Task {
                await cursor.apply(.standard)
                draft = cursor.colors
              }
            }.disabled(!cursor.available || cursor.isApplying || cursor.isLoading)
          }

          VStack(alignment: .leading, spacing: 4) {
            Text(
              "Save Combination keeps these colors for later. Save & Apply also changes the pointer."
            )
            .fixedSize(horizontal: false, vertical: true)
            if let savedMessage { Text(savedMessage) }
          }
          .font(DeckStyle.caption).foregroundStyle(.secondary)
        }
        .padding(inset)

        if let error = cursor.error {
          DeckSeparator(leadingInset: inset)
          DeckNotice(message: error) {
            Button("Refresh") { Task { await cursor.refresh() } }
            Button("Full Disk Access…") { CursorColorMenu.openFullDiskAccess() }
            Button("Open Pointer Settings…") { CursorColorMenu.openPointerSettings() }
          }
          .padding(inset)
        }
      }

      PaneSection(title: "Saved Combinations") {
        if cursor.palettes.savedColors.isEmpty {
          Text("Save a fill and outline pair to reuse it here or in the dropdown.")
            .font(DeckStyle.value).foregroundStyle(.secondary)
            .padding(inset)
        } else {
          ForEach(Array(cursor.palettes.savedColors.enumerated()), id: \.element.id) {
            index, saved in
            if index > 0 {
              DeckSeparator(leadingInset: inset + DeckStyle.tileSize + DeckStyle.rowSpacing)
            }
            savedRow(saved)
          }
        }
      }

      Button("Open Pointer Settings…") { CursorColorMenu.openPointerSettings() }
    }
    .onAppear { draft = cursor.colors }
    .onChange(of: cursor.colors) { old, new in if draft == old { draft = new } }
    .task {
      await cursor.refresh(clearError: false)
      await pointer.refresh(clearError: false)
    }
  }

  private func savedRow(_ saved: SavedCursorPalette) -> some View {
    let isCurrent = cursor.palettes.matching(cursor.colors)?.id == saved.id
    return HStack(spacing: DeckStyle.rowSpacing) {
      CursorArrowTile(colors: saved.colors)
      Text(saved.name).font(DeckStyle.rowTitle).lineLimit(1).help(saved.name)
      Spacer(minLength: 8)
      if isCurrent {
        Label("Current", systemImage: "checkmark")
          .font(DeckStyle.caption).foregroundStyle(.secondary)
      }
      Button("Apply") {
        name = ""
        Task {
          await cursor.apply(saved.colors)
          draft = cursor.colors
        }
      }
      .controlSize(.small)
      .disabled(
        cursor.isLoading || cursor.isApplying || !cursor.available
          || (cursor.colors.matches(saved.colors)
            && cursor.colors.customized == saved.colors.customized)
      )
      Button {
        cursor.palettes.remove(saved.id)
      } label: {
        Image(systemName: "trash")
      }
      .buttonStyle(.borderless)
      .disabled(isCurrent)
      .help(
        isCurrent
          ? "Choose another combination before removing the current one."
          : "Remove \(saved.name)"
      )
      .accessibilityLabel("Remove saved combination \(saved.name)")
    }
    .padding(.horizontal, inset)
    .frame(minHeight: 44)
  }

  private func saveDraft() {
    if let saved = cursor.palettes.save(draft, name: name) {
      savedMessage = "Saved \(saved.name)."
      name = ""
    }
  }

  private func sample(background: Color, name: String) -> some View {
    ZStack {
      background
      CursorArrowPreview(colors: draft).frame(width: 36, height: 48)
    }.frame(maxWidth: .infinity).accessibilityLabel(name)
  }

  private func colorBinding(fill: Bool) -> Binding<Color> {
    Binding(
      get: { Color(nsColor: (fill ? draft.fill : draft.outline).nsColor) },
      set: { value in
        guard let converted = CursorRGB(NSColor(value)) else { return }
        draft = CursorColors(
          fill: fill ? converted : draft.fill, outline: fill ? draft.outline : converted,
          customized: true)
        savedMessage = nil
      })
  }
}

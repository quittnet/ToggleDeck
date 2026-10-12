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

@MainActor
struct CursorColorMenu: View {
  @ObservedObject var cursor: CursorColorController
  @ObservedObject var pointer: PointerController = .shared
  var onCustom: () -> Void
  var onChoose: (CursorColors) -> Void = { _ in }
  var snapshot = false
  var showCustom = true

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
        HStack(spacing: 10) {
          CursorArrowPreview(colors: cursor.colors).frame(width: 22, height: 26)
          VStack(alignment: .leading, spacing: 1) {
            Menu {
              if !cursor.palettes.savedColors.isEmpty {
                Section("Saved Combinations") {
                  ForEach(cursor.palettes.savedColors) { saved in
                    colorChoice(saved.name, colors: saved.colors)
                  }
                }
              }
              Section("Color Combinations") {
                ForEach(CursorPreset.combinationPresets) { preset in
                  colorChoice(preset.rawValue, colors: preset.colors)
                }
              }
              Section("Colors") {
                ForEach(CursorPreset.solidPresets) { preset in
                  colorChoice(preset.rawValue, colors: preset.colors)
                }
              }
              Divider()
              Menu("Pointer Size") {
                ForEach([1.0, 1.25, 1.5, 2.0, 3.0, 4.0], id: \.self) { scale in
                  Button("\(Int(scale * 100))%") {
                    Task {
                      await pointer.apply(
                        PointerSettings(
                          scale: scale, shakeToFind: pointer.settings.shakeToFind))
                    }
                  }
                }
              }.disabled(pointer.isLoading || pointer.isApplying || !pointer.available)
              Toggle(
                "Shake to Find Pointer",
                isOn: Binding(
                  get: { pointer.settings.shakeToFind },
                  set: { enabled in
                    Task {
                      await pointer.apply(
                        PointerSettings(
                          scale: pointer.settings.scale, shakeToFind: enabled))
                    }
                  })
              )
              .disabled(pointer.isLoading || pointer.isApplying || !pointer.available)
              Divider()
              Button("Save Current Combination") { cursor.palettes.save(cursor.colors) }
                .disabled(
                  cursor.isLoading || cursor.isApplying || !cursor.available
                    || cursor.palettes.matching(cursor.colors) != nil)
              Divider()
              if showCustom { Button("Custom Colors…", action: onCustom) }
              Button("Refresh Cursor Settings") {
                Task {
                  await cursor.refresh()
                  await pointer.refresh()
                }
              }
              .disabled(
                cursor.isRefreshing || cursor.isApplying || pointer.isRefreshing
                  || pointer.isApplying)
              if error != nil {
                Button("Full Disk Access…") { Self.openFullDiskAccess() }
              }
              Button("Open Pointer Settings…") { Self.openPointerSettings() }
            } label: {
              Text("Cursor Color · \(status)").font(.system(size: 13, weight: .medium))
            }
            .menuStyle(.borderlessButton).menuIndicator(.visible)
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(cursor.isApplying)
            .accessibilityLabel("Cursor Color: \(status)")
            .accessibilityHint(
              error ?? "Choose colors, adjust pointer size, or enable shake to locate.")
            if error != nil {
              Text("Needs attention · details in menu")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
          }
        }.padding(.horizontal, 10)
      }
    }
    .frame(height: 40)
    .help(error ?? "Change your Mac's pointer color, size, and shake to locate")
  }

  private func colorChoice(_ name: String, colors: CursorColors) -> some View {
    Button {
      Task {
        await cursor.apply(colors)
        onChoose(cursor.colors)
      }
    } label: {
      HStack {
        Text(name)
        if cursor.colors.matches(colors) && cursor.colors.customized == colors.customized {
          Image(systemName: "checkmark")
        }
      }
    }.disabled(cursor.isLoading || cursor.isApplying || !cursor.available)
  }

  private var label: some View {
    HStack(spacing: 10) {
      CursorArrowPreview(colors: cursor.colors).frame(width: 22, height: 26)
      VStack(alignment: .leading, spacing: 2) {
        Text("Cursor Color").font(.system(size: 13, weight: .medium))
        if error != nil {
          Text("Needs attention · details in menu").font(.system(size: 10.5)).foregroundStyle(
            .secondary)
        }
      }
      Spacer(minLength: 6)
      if cursor.isApplying && !snapshot { ProgressView().controlSize(.small) }
      Text(status).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
      Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(
        .secondary)
    }.padding(.horizontal, 10).frame(maxWidth: .infinity, alignment: .leading).contentShape(
      Rectangle())
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
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    {
      NSWorkspace.shared.open(url)
    }
  }
}

@MainActor
struct CursorColorsPane: View {
  @ObservedObject var cursor: CursorColorController
  @ObservedObject var pointer: PointerController = .shared
  @ViewState<CursorColors> private var draft = .standard
  @ViewState<String> private var name = ""
  @ViewState<String?> private var savedMessage = nil

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
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Cursor Settings").font(.system(size: 17, weight: .semibold))
          Text("Adjust your Mac’s pointer size, visibility, and colors.").font(.system(size: 12))
            .foregroundStyle(
              .secondary)
        }
        PointerControlsView(pointer: pointer)
        Divider()
        Text("Cursor Colors").font(.system(size: 14, weight: .semibold))
        HStack(spacing: 1) {
          sample(background: .white, name: "Light background")
          sample(background: Color(white: 0.12), name: "Dark background")
        }
        .frame(height: 104).clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)) }

        CursorColorMenu(
          cursor: cursor, pointer: pointer, onCustom: {},
          onChoose: { draft = $0 }, showCustom: false
        )
        .frame(maxWidth: 330)

        VStack(spacing: 14) {
          ColorPicker("Fill color", selection: colorBinding(fill: true), supportsOpacity: false)
            .accessibilityLabel("Cursor fill color")
          ColorPicker("Outline color", selection: colorBinding(fill: false), supportsOpacity: false)
            .accessibilityLabel("Cursor outline color")
        }.font(.system(size: 13)).frame(maxWidth: 330)
          .disabled(cursor.isLoading || cursor.isApplying)

        TextField("Combination name (optional)", text: $name)
          .textFieldStyle(.roundedBorder).frame(maxWidth: 330)
          .accessibilityLabel("Saved combination name")

        HStack(spacing: 12) {
          Button(cursor.isApplying ? "Applying…" : "Save & Apply") {
            let requested = draft
            saveDraft()
            Task { await cursor.apply(requested) }
          }.buttonStyle(.borderedProminent).disabled(!canApply)
          Button("Save Combination", action: saveDraft).disabled(!canSave)
          Button("Reset to Default") {
            draft = .standard
            Task { await cursor.apply(.standard) }
          }.disabled(!cursor.available || cursor.isApplying || cursor.isLoading)
        }
        Text(
          "Save Combination keeps these colors for later. Save & Apply also changes the pointer."
        )
        .font(.system(size: 11)).foregroundStyle(.secondary)
        if let savedMessage {
          Text(savedMessage).font(.system(size: 11)).foregroundStyle(.secondary)
        }

        if let error = cursor.error {
          VStack(alignment: .leading, spacing: 8) {
            Label(error, systemImage: "exclamationmark.circle.fill")
              .font(.system(size: 12)).foregroundStyle(.primary).fixedSize(
                horizontal: false, vertical: true)
            HStack {
              Button("Refresh") { Task { await cursor.refresh() } }
              Button("Full Disk Access…") { CursorColorMenu.openFullDiskAccess() }
              Button("Open Pointer Settings…") { CursorColorMenu.openPointerSettings() }
            }.font(.system(size: 12))
          }
        }

        VStack(alignment: .leading, spacing: 8) {
          Text("Saved Combinations").font(.system(size: 14, weight: .semibold))
          if cursor.palettes.savedColors.isEmpty {
            Text("Save a fill and outline pair to reuse it here or in the dropdown.")
              .font(.system(size: 12)).foregroundStyle(.secondary)
          } else {
            ForEach(cursor.palettes.savedColors) { saved in
              HStack(spacing: 10) {
                CursorArrowPreview(colors: saved.colors).frame(width: 20, height: 26)
                Text(saved.name).font(.system(size: 13)).lineLimit(1).help(saved.name)
                Spacer()
                if cursor.palettes.matching(cursor.colors)?.id == saved.id {
                  Label("Current", systemImage: "checkmark")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Button("Apply") {
                  name = ""
                  Task {
                    await cursor.apply(saved.colors)
                    draft = cursor.colors
                  }
                }.disabled(
                  cursor.isLoading || cursor.isApplying || !cursor.available
                    || (cursor.colors.matches(saved.colors)
                      && cursor.colors.customized == saved.colors.customized)
                )
                Button {
                  cursor.palettes.remove(saved.id)
                } label: {
                  Image(systemName: "trash")
                }.buttonStyle(.borderless)
                  .disabled(cursor.palettes.matching(cursor.colors)?.id == saved.id)
                  .help(
                    cursor.palettes.matching(cursor.colors)?.id == saved.id
                      ? "Choose another combination before removing the current one."
                      : "Remove \(saved.name)"
                  )
                  .accessibilityLabel("Remove saved combination \(saved.name)")
              }.padding(.vertical, 5)
            }
          }
        }
      }
      .padding(22).frame(maxWidth: .infinity, alignment: .leading)
    }
    .onAppear { draft = cursor.colors }
    .onChange(of: cursor.colors) { old, new in if draft == old { draft = new } }
    .task {
      await cursor.refresh(clearError: false)
      await pointer.refresh(clearError: false)
    }
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

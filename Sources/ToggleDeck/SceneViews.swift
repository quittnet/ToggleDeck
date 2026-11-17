import SwiftUI

// MARK: - Dropdown strip

/// One row of scene chips under the search field. It scrolls sideways, so
/// any number of scenes keeps the fixed height the layout engine counts.
struct SceneStrip: View {
  @ObservedObject var scenes: SceneStore
  @ObservedObject var engine: ToggleEngine
  var snapshot = false
  var onEdit: () -> Void = {}

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 6) {
        ForEach(scenes.scenes) { scene in chip(scene) }
      }
      .padding(.horizontal, DeckStyle.panelInset)
    }
    .frame(height: DropdownChrome.sceneChipHeight)
    .padding(.bottom, DropdownChrome.sceneStripBottomPadding)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Scenes")
  }

  private func chip(_ scene: DeckScene) -> some View {
    let active = SceneStore.isActive(scene, engine: engine)
    let running = scenes.applying == scene.id
    let empty = scene.targets.isEmpty
    return Button {
      Task { await scenes.apply(scene, engine: engine) }
    } label: {
      HStack(spacing: 5) {
        if running && !snapshot {
          ProgressView().controlSize(.mini)
        } else {
          Image(systemName: active ? "checkmark.circle.fill" : "sparkles")
            .font(.system(size: 10, weight: .semibold))
        }
        Text(scene.name.isEmpty ? "Untitled" : scene.name)
      }
    }
    .buttonStyle(SceneChipButtonStyle(isActive: active))
    .disabled(scenes.applying != nil || empty)
    .help(
      empty
        ? "This scene has no switches yet. Edit it in Settings."
        : scene.specs.map { spec in
          let on = scene.targets.first { $0.id == spec.id }?.on == true
          return "\(spec.menuTitle): \(on ? "On" : "Off")"
        }.joined(separator: "\n")
    )
    .accessibilityLabel("Apply scene \(scene.name)")
    .accessibilityValue(active ? "Active" : "")
    .contextMenu { Button("Edit Scenes…", action: onEdit) }
  }
}

private struct SceneChipButtonStyle: ButtonStyle {
  let isActive: Bool
  @ViewState<Bool> private var hovered = false
  @Environment(\.isEnabled) private var enabled

  func makeBody(configuration: Configuration) -> some View {
    let shape = Capsule()
    let base: Color = isActive ? Color.accentColor.opacity(0.16) : DeckStyle.quietFill
    let fill: Color =
      if enabled && configuration.isPressed {
        Color.primary.opacity(0.18)
      } else if enabled && hovered {
        isActive ? Color.accentColor.opacity(0.24) : DeckStyle.pressedFill
      } else {
        base
      }
    configuration.label
      .font(DeckStyle.caption.weight(.medium))
      .foregroundStyle(isActive ? Color.accentColor : Color.primary)
      .lineLimit(1)
      .padding(.horizontal, 10)
      .frame(height: DropdownChrome.sceneChipHeight)
      .background(fill, in: shape)
      .contentShape(shape)
      .opacity(enabled ? 1 : 0.55)
      .onHover { hovered = $0 }
  }
}

// MARK: - Settings pane

@MainActor
struct ScenesPane: View {
  @ObservedObject var scenes: SceneStore
  @ObservedObject var engine: ToggleEngine

  var body: some View {
    PaneScaffold {
      PaneHeader(
        title: "Scenes",
        subtitle:
          "Set several switches at once from the menu. Each scene sets only the switches listed in it."
      ) {
        Button {
          scenes.add()
        } label: {
          Label("New Scene", systemImage: "plus")
        }.controlSize(.regular)
      }

      if scenes.scenes.isEmpty {
        ContentUnavailableView {
          Label("No scenes", systemImage: "sparkles")
        } description: {
          Text("A scene appears above your controls in the menu and applies with one click.")
        } actions: {
          Button("Add “Presenting”") { scenes.add(.presenting) }
          Button("New Scene") { scenes.add() }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
        .deckCard()
      } else {
        ForEach($scenes.scenes) { $scene in
          SceneCard(scene: $scene, scenes: scenes, engine: engine)
        }
      }
    }
  }
}

@MainActor
private struct SceneCard: View {
  @Binding var scene: DeckScene
  @ObservedObject var scenes: SceneStore
  @ObservedObject var engine: ToggleEngine

  var body: some View {
    PaneSection {
      HStack(spacing: 10) {
        TextField("Scene name", text: $scene.name)
          .textFieldStyle(.plain).font(DeckStyle.cardTitle)
          .accessibilityLabel("Scene name")
        Spacer(minLength: 8)
        Button("Apply") { Task { await scenes.apply(scene, engine: engine) } }
          .controlSize(.small)
          .disabled(scenes.applying != nil || scene.targets.isEmpty)
        Button {
          scenes.remove(scene.id)
        } label: {
          Image(systemName: "trash").frame(width: 22, height: 22)
        }
        .buttonStyle(DeckButtonStyle()).help("Delete scene")
        .accessibilityLabel("Delete scene \(scene.name)")
      }
      .settingsRowPadding()

      ForEach(scene.specs) { spec in
        SettingsSeparator()
        targetRow(spec)
      }

      SettingsSeparator()
      HStack(spacing: 10) {
        addMenu
        Spacer()
        Button("Use Current Positions") { scenes.capture(scene.id, engine: engine) }
          .controlSize(.small).disabled(scene.targets.isEmpty)
          .help("Set each switch in this scene to where it is on your Mac right now")
      }
      .settingsRowPadding()
    }
  }

  private func targetRow(_ spec: ToggleSpec) -> some View {
    let on = Binding<Bool>(
      get: { scene.targets.first { $0.id == spec.id }?.on ?? false },
      set: { value in
        if let index = scene.targets.firstIndex(where: { $0.id == spec.id }) {
          scene.targets[index].on = value
        }
      })
    return HStack(spacing: DeckStyle.rowSpacing) {
      IconTile(
        symbol: spec.menuSymbol(isOn: on.wrappedValue), tint: spec.category.tint,
        isLit: on.wrappedValue, size: DeckStyle.smallTileSize)
      Text(spec.menuTitle).font(DeckStyle.rowTitle).lineLimit(1)
      Spacer(minLength: 8)
      Text(on.wrappedValue ? "Turn On" : "Turn Off")
        .font(DeckStyle.caption).foregroundStyle(.secondary)
      Toggle("Turn \(spec.menuTitle) on", isOn: on).settingsSwitch()
      Button {
        scenes.removeTarget(spec.id, from: scene.id)
      } label: {
        Image(systemName: "minus.circle").frame(width: 22, height: 22)
      }
      .buttonStyle(DeckButtonStyle()).help("Remove from scene")
      .accessibilityLabel("Remove \(spec.menuTitle) from \(scene.name)")
    }
    .padding(.horizontal, DeckStyle.cardInset).padding(.vertical, 6)
  }

  private var addMenu: some View {
    Menu {
      ForEach(Category.allCases) { category in
        let available = Catalog.all.filter { $0.category == category && !scene.contains($0.id) }
        if !available.isEmpty {
          Section(category.rawValue) {
            ForEach(available) { spec in
              Button(spec.menuTitle) {
                scenes.addTarget(spec.id, to: scene.id, engine: engine)
              }
            }
          }
        }
      }
    } label: {
      Label("Add Switch", systemImage: "plus")
    }
    .menuStyle(.button).controlSize(.small).fixedSize()
  }
}

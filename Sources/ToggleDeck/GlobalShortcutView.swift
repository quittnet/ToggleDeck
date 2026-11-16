import SwiftUI

/// The keyboard shortcut card of the General pane.
@MainActor
struct GlobalShortcutView: View {
  @ObservedObject var controller: GlobalShortcutController
  @ViewState<GlobalShortcutKey> private var key = .t
  @ViewState<GlobalShortcutModifiers> private var modifiers: GlobalShortcutModifiers = [
    .control, .option, .command,
  ]

  init(controller: GlobalShortcutController = .shared) { self.controller = controller }

  private var draft: GlobalShortcut { GlobalShortcut(key: key, modifiers: modifiers) }

  var body: some View {
    PaneSection(title: "Keyboard Shortcut") {
      SettingsRow(title: "Open menu with a keyboard shortcut", caption: status) {
        Toggle(
          "Open menu with a keyboard shortcut",
          isOn: Binding(get: { controller.enabled }, set: { controller.setEnabled($0) })
        )
        .settingsSwitch()
      }
      SettingsSeparator()
      SettingsRow(title: "Key") {
        Picker("Key", selection: $key) {
          ForEach(GlobalShortcutKey.allCases) { key in Text(key.title).tag(key) }
        }
        .labelsHidden().fixedSize()
        .help("Letter keys use US keyboard positions. Function keys may require Fn.")
      }
      SettingsSeparator()
      SettingsRow(title: "Modifiers") {
        HStack(spacing: 12) {
          modifier("Control", .control)
          modifier("Option", .option)
          modifier("Shift", .shift)
          modifier("Command", .command)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Modifiers")
      }
      .accessibilityElement(children: .contain)
      SettingsSeparator()
      shortcutRow
    }
    .onAppear { loadSavedShortcut() }
    .onChange(of: controller.shortcut) { _, _ in loadSavedShortcut() }
  }

  private var status: String? {
    if !controller.enabled { return "Shortcut disabled." }
    if let active = controller.activeShortcut {
      return "\(active.displayName) opens or closes ToggleDeck from any app."
    }
    if controller.error == nil { return "Open or close ToggleDeck while using another app." }
    return nil
  }

  private var shortcutRow: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text(draft.displayName).font(.system(size: 15, weight: .medium))
          .accessibilityLabel("Shortcut: \(draft.displayName)")
        if draft != controller.shortcut {
          Text("Not in use yet").font(DeckStyle.caption).foregroundStyle(.secondary)
        }
        if !draft.isValid {
          Text("Include Control or Command to avoid interrupting typing.")
            .font(DeckStyle.caption).foregroundStyle(.secondary)
        }
        if let error = controller.error {
          Text(error).font(DeckStyle.caption).foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 12)
      Button("Restore Default") {
        key = GlobalShortcut.default.key
        modifiers = GlobalShortcut.default.modifiers
        controller.update(.default)
      }
      Button("Use Shortcut") { controller.update(draft) }
        .disabled(!draft.isValid || (draft == controller.shortcut && controller.error == nil))
    }
    .settingsRowPadding()
  }

  private func loadSavedShortcut() {
    key = controller.shortcut.key
    modifiers = controller.shortcut.modifiers
  }

  private func modifier(_ title: String, _ value: GlobalShortcutModifiers) -> some View {
    Toggle(
      title,
      isOn: Binding(
        get: { modifiers.contains(value) },
        set: { selected in
          if selected { modifiers.insert(value) } else { modifiers.remove(value) }
        })
    ).toggleStyle(.checkbox).font(DeckStyle.value)
  }
}

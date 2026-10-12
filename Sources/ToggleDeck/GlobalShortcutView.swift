import SwiftUI

/// Insert this native section inside the General pane's grouped Form.
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
    Section("Keyboard Shortcut") {
      Toggle(
        "Open menu with a keyboard shortcut",
        isOn: Binding(get: { controller.enabled }, set: { controller.setEnabled($0) }))
      Picker("Key", selection: $key) {
        ForEach(GlobalShortcutKey.allCases) { key in Text(key.title).tag(key) }
      }
      .help("Letter keys use US keyboard positions. Function keys may require Fn.")

      LabeledContent("Modifiers") {
        HStack(spacing: 10) {
          modifier("Control", .control)
          modifier("Option", .option)
          modifier("Shift", .shift)
          modifier("Command", .command)
        }
        .accessibilityElement(children: .contain)
      }
      .accessibilityElement(children: .contain)
      HStack {
        Text(draft.displayName).font(.system(size: 13, weight: .medium))
          .accessibilityLabel("Shortcut: \(draft.displayName)")
        Spacer()
        Button("Restore Default") {
          key = GlobalShortcut.default.key
          modifiers = GlobalShortcut.default.modifiers
          controller.update(.default)
        }
        Button("Use Shortcut") { controller.update(draft) }
          .disabled(!draft.isValid || (draft == controller.shortcut && controller.error == nil))
      }
      if !draft.isValid {
        Text("Include Control or Command to avoid interrupting typing.")
          .font(.system(size: 11)).foregroundStyle(.secondary)
      }
      if let error = controller.error {
        Text(error).font(.system(size: 11)).foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      }
      if !controller.enabled {
        Text("Shortcut disabled.").font(.system(size: 10.5)).foregroundStyle(.secondary)
      } else if let active = controller.activeShortcut {
        Text("\(active.displayName) opens or closes ToggleDeck from any app.")
          .font(.system(size: 10.5)).foregroundStyle(.secondary)
      } else if controller.error == nil {
        Text("Open or close ToggleDeck while using another app.")
          .font(.system(size: 10.5)).foregroundStyle(.secondary)
      }
    }
    .onAppear { loadSavedShortcut() }
    .onChange(of: controller.shortcut) { _, _ in loadSavedShortcut() }
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
    ).toggleStyle(.checkbox).font(.system(size: 11))
  }
}

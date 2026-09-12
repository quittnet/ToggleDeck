import AppKit
import SwiftUI

@MainActor
struct DropdownView: View {
  @ObservedObject var engine = ToggleEngine.shared
  @ObservedObject var settings = AppSettings.shared
  @State private var query = ""
  @FocusState private var searchFocused: Bool
  @FocusState private var focusedControl: String?

  var onOpenSettings: () -> Void
  var onQuit: () -> Void
  var onClose: () -> Void = {}
  var onSizeChange: (CGSize) -> Void = { _ in }
  var previewSpecs: [ToggleSpec]?
  var snapshotSearch: String?

  private var search: String { snapshotSearch ?? query }
  private var searching: Bool { !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  private var visible: [ToggleSpec] {
    let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if searching { return Catalog.all.filter { $0.searchBlob.contains(needle) } }
    return previewSpecs ?? settings.pinnedSpecs
  }

  private var items: [DropdownLayout.Item] {
    guard settings.groupDropdown || searching else { return visible.map { .row($0) } }
    let groups = Dictionary(grouping: visible, by: \.category)
    return Category.allCases.flatMap { category -> [DropdownLayout.Item] in
      guard let rows = groups[category], !rows.isEmpty else { return [] }
      return [.header(category)] + rows.map { .row($0) }
    }
  }

  private var layout: DropdownLayout.Result {
    DropdownLayout.pack(
      items, showDescriptions: settings.showDescriptions,
      extraChrome: engine.banner == nil ? 0 : 76)
  }

  var body: some View {
    let packed = layout
    VStack(spacing: 0) {
      header
      Divider().padding(.horizontal, 16)
      if visible.isEmpty {
        empty
      } else {
        HStack(alignment: .top, spacing: 16) {
          ForEach(Array(packed.columns.enumerated()), id: \.offset) { _, column in
            columnView(column, scrolls: packed.overflowed)
              .frame(width: packed.columnWidth)
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .fixedSize(horizontal: false, vertical: true)
      }
      if let message = engine.banner { banner(message) }
      Divider().padding(.horizontal, 16)
      footer
    }
    .frame(width: packed.width)
    .background(Color(nsColor: .windowBackgroundColor))
    .background {
      GeometryReader { geometry in
        Color.clear.task(id: geometry.size) { onSizeChange(geometry.size) }
      }
    }
    .task { await engine.refreshAll() }
    .onAppear { searchFocused = true }
    .onChange(of: query) { _, _ in focusedControl = nil }
    .onExitCommand {
      if searching {
        query = ""
        searchFocused = true
      } else {
        onClose()
      }
    }
    .onMoveCommand { direction in
      if direction == .down { moveFocus(1) } else if direction == .up { moveFocus(-1) }
    }
  }

  private var header: some View {
    VStack(spacing: 12) {
      HStack(spacing: 9) {
        Image(nsImage: NSApp.applicationIconImage)
          .resizable().frame(width: 28, height: 28).accessibilityHidden(true)
        Text("ToggleDeck").font(.system(size: 15, weight: .semibold))
        Spacer()
        Button {
          Task { await engine.refreshAll() }
        } label: {
          Image(systemName: "arrow.clockwise").frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(engine.isRefreshing)
        .help("Refresh settings (Command-R)").accessibilityLabel("Refresh settings")
        .keyboardShortcut("r", modifiers: .command)
        if snapshotSearch != nil {
          // ImageRenderer does not draw AppKit-backed menus. The live menu uses
          // this same symbol and size, while snapshots draw its SwiftUI label.
          Image(systemName: "ellipsis").frame(width: 28, height: 28)
        } else {
          Menu {
            Button("Customize Menu…", action: onOpenSettings)
            Divider()
            Button("Quit ToggleDeck", action: onQuit).keyboardShortcut("q", modifiers: .command)
          } label: {
            Image(systemName: "ellipsis").frame(width: 28, height: 28)
          }
          .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
          .accessibilityLabel("More options")
        }
        Button(action: onClose) {
          Image(systemName: "xmark").frame(width: 28, height: 28)
        }
        .buttonStyle(.plain).help("Close menu (Escape)").accessibilityLabel("Close menu")
      }
      HStack(spacing: 8) {
        Button {
          searchFocused = true
        } label: {
          Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        }
        .buttonStyle(.plain).keyboardShortcut("f", modifiers: .command)
        .accessibilityLabel("Focus search")
        if snapshotSearch != nil {
          Text(search.isEmpty ? "Find a setting" : search)
            .foregroundStyle(search.isEmpty ? .secondary : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
          TextField("Find a setting", text: $query)
            .textFieldStyle(.plain).focused($searchFocused)
            .accessibilityLabel("Find a setting")
            .onSubmit {
              focusedControl =
                visible.first {
                  let state = engine.state($0.id)
                  return state.supported && !state.stale && !state.busy
                }?.id
              searchFocused = false
            }
        }
        if searching {
          Button {
            query = ""
            searchFocused = true
          } label: {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
          }
          .buttonStyle(.plain).accessibilityLabel("Clear search")
        } else {
          Text("⌘F").font(.system(size: 11)).foregroundStyle(.secondary).accessibilityHidden(true)
        }
      }
      .font(.system(size: 13))
      .padding(.horizontal, 10).frame(height: 32)
      .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .strokeBorder(
            searchFocused ? Color.accentColor.opacity(0.75) : Color.primary.opacity(0.10),
            lineWidth: 1)
      }
    }
    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
  }

  @ViewBuilder
  private func columnView(_ column: [DropdownLayout.Item], scrolls: Bool) -> some View {
    let content = VStack(alignment: .leading, spacing: 0) {
      ForEach(column) { item in
        switch item {
        case .header(let category):
          Text(category.rawValue)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
            .frame(height: 30, alignment: .bottom)
            .accessibilityAddTraits(.isHeader)
        case .row(let spec):
          DropdownControlRow(
            spec: spec, state: engine.state(spec.id),
            showDescriptions: settings.showDescriptions,
            isFocused: focusedControl == spec.id
          ) {
            Task { await engine.set(spec.id, on: !engine.state(spec.id).isOn) }
          }
          .focused($focusedControl, equals: spec.id)
        }
      }
    }
    if scrolls {
      ScrollView { content }
        .frame(
          maxHeight: DropdownLayout.availableHeight(
            .init(showDescriptions: settings.showDescriptions)))
    } else {
      content
    }
  }

  private var footer: some View {
    HStack {
      Text(
        searching
          ? "\(visible.count) \(visible.count == 1 ? "result" : "results")"
          : "\(settings.pinned.count) controls"
      )
      .font(.system(size: 11)).foregroundStyle(.secondary)
      Spacer()
      Button(action: onOpenSettings) {
        Label("Customize", systemImage: "slider.horizontal.3")
          .font(.system(size: 12, weight: .medium))
      }
      .buttonStyle(.plain).help("Choose and reorder menu controls")
    }
    .padding(.horizontal, 18).frame(height: 44)
  }

  private var empty: some View {
    VStack(spacing: 10) {
      Image(systemName: searching ? "magnifyingglass" : "pin.slash")
        .font(.system(size: 24)).foregroundStyle(.secondary)
      Text(searching ? "No matching settings" : "Your menu is empty")
        .font(.system(size: 14, weight: .medium))
      Text(
        searching
          ? "Try a name like Wi-Fi, Dock, or sound." : "Choose the controls you want in your menu."
      )
      .font(.system(size: 12)).foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      Button(searching ? "Clear search" : "Customize Menu…") {
        if searching {
          query = ""
          searchFocused = true
        } else {
          onOpenSettings()
        }
      }
      .controlSize(.small)
    }
    .padding(24).frame(maxWidth: .infinity).frame(minHeight: 200)
  }

  private func banner(_ message: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
      Text(message).font(.system(size: 11)).lineLimit(3)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button {
        engine.banner = nil
      } label: {
        Image(systemName: "xmark")
      }
      .buttonStyle(.plain).accessibilityLabel("Dismiss message")
    }
    .padding(12).background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
    .padding(.horizontal, 16).padding(.bottom, 10)
  }

  private func moveFocus(_ step: Int) {
    let ids = layout.columns.flatMap { $0 }.compactMap { item -> String? in
      guard case .row(let spec) = item else { return nil }
      let state = engine.state(spec.id)
      return state.supported && !state.stale && !state.busy ? spec.id : nil
    }
    guard !ids.isEmpty else { return }
    let current = focusedControl.flatMap { ids.firstIndex(of: $0) } ?? (step > 0 ? -1 : ids.count)
    focusedControl = ids[min(max(current + step, 0), ids.count - 1)]
    searchFocused = false
  }
}

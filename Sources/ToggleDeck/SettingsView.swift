import AppKit
import SwiftUI

enum SettingsSection: Hashable {
  case general
  case dropdown
  case cursor
  case sound
  case all
  case category(Category)

  var title: String {
    switch self {
    case .general: return "General"
    case .dropdown: return "Your Menu"
    case .cursor: return "Cursor"
    case .sound: return "Sound"
    case .all: return "Everyday Settings"
    case .category(let c): return c.rawValue
    }
  }

  var symbol: String {
    switch self {
    case .general: return "gearshape"
    case .dropdown: return "menubar.arrow.down.rectangle"
    case .cursor: return "cursorarrow"
    case .sound: return "speaker.wave.2"
    case .all: return "square.grid.2x2"
    case .category(let c): return c.symbol
    }
  }
}

@MainActor
struct SettingsView: View {
  @ObservedObject var engine: ToggleEngine
  @ObservedObject var settings: AppSettings
  @ObservedObject var cursor: CursorColorController
  @ObservedObject var pointer: PointerController
  @ObservedObject var audio: AudioController
  @ObservedObject var shortcut: GlobalShortcutController

  @ViewState<SettingsSection> private var section: SettingsSection
  @ViewState<String> private var query = ""
  @FocusState private var searchFocused: Bool

  init(
    initialSection: SettingsSection = .dropdown, engine: ToggleEngine = .shared,
    settings: AppSettings = .shared, cursor: CursorColorController = .shared,
    pointer: PointerController = .shared, audio: AudioController = .shared,
    shortcut: GlobalShortcutController = .shared
  ) {
    self.engine = engine
    self.settings = settings
    self.cursor = cursor
    self.pointer = pointer
    self.audio = audio
    self.shortcut = shortcut
    _section = State(initialValue: initialSection)
  }

  var body: some View {
    NavigationSplitView {
      sidebar
    } detail: {
      VStack(spacing: 0) {
        detail
        if engine.banner != nil { FeedbackView(engine: engine).padding(16) }
      }.frame(minWidth: 520)
    }
    .frame(minWidth: 860, minHeight: 600)
    .task { await engine.refreshAll() }
    .onChange(of: section) { _, _ in query = "" }
    .onExitCommand { query = "" }
    .background {
      Button("") { searchFocused = true }.keyboardShortcut("f", modifiers: .command).hidden()
    }
  }

  // MARK: Sidebar

  private var sidebar: some View {
    List(selection: $section) {
      Section {
        row(.general)
        row(.dropdown)
        row(.cursor)
        row(.sound)
        row(.all)
      }
      Section("Categories") {
        ForEach(Category.allCases) { cat in
          row(.category(cat), count: Catalog.all.filter { $0.category == cat }.count)
        }
      }
    }
    .listStyle(.sidebar)
    .frame(minWidth: 218)
    .safeAreaInset(edge: .bottom) {
      HStack {
        Text("\(Catalog.all.count) toggles + cursor + sound")
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
        Spacer()
        if engine.isRefreshing {
          ProgressView().controlSize(.small).scaleEffect(0.6)
        }
        Button {
          Task {
            await cursor.refresh()
            await pointer.refresh()
            await audio.refresh()
            await engine.refreshAll()
          }
        } label: {
          Image(systemName: "arrow.clockwise").font(.system(size: 10))
        }
        .buttonStyle(.plain)
        .help("Re-read every setting")
      }
      .padding(.horizontal, 12).padding(.vertical, 7)
      .background(.bar)
    }
  }

  private func row(_ s: SettingsSection, count: Int? = nil) -> some View {
    HStack {
      Label(s.title, systemImage: s.symbol)
      Spacer()
      if let count {
        Text("\(count)")
          .font(.system(size: 10))
          .foregroundStyle(.tertiary)
      }
    }
    .tag(s)
  }

  // MARK: Detail

  @ViewBuilder
  private var detail: some View {
    switch section {
    case .general: GeneralPane(settings: settings, engine: engine, shortcut: shortcut)
    case .dropdown: DropdownPane(settings: settings, engine: engine)
    case .cursor: CursorColorsPane(cursor: cursor, pointer: pointer)
    case .sound: AudioPane(audio: audio)
    case .all: listPane(Catalog.all, title: "Everyday Settings", showCategory: true)
    case .category(let cat):
      listPane(Catalog.all.filter { $0.category == cat }, title: cat.rawValue, showCategory: false)
    }
  }

  private func listPane(_ specs: [ToggleSpec], title: String, showCategory: Bool) -> some View {
    let filtered = SettingSearch.results(in: specs, query: query)

    return VStack(spacing: 0) {
      paneHeader(
        title: title,
        subtitle:
          "Add controls to your menu with the pin button. Right-click for more options.",
        search: true)

      if filtered.isEmpty {
        ContentUnavailableView(
          "No matches", systemImage: "magnifyingglass",
          description: Text("Nothing in this section matches \"\(query)\"."))
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(filtered) { spec in
              ToggleRow(
                spec: spec, engine: engine, settings: settings,
                showPin: true, showDetail: true, showCategory: showCategory
              )
              .padding(.horizontal, 18)
              Divider().opacity(0.35).padding(.leading, 18)
            }
          }
          .padding(.vertical, 4)
        }
      }
    }
  }

  /// The search field is drawn inline rather than via `.searchable`. That
  /// modifier installs itself in the window toolbar, and this window has no
  /// NSToolbar, so the field could silently fail to appear.
  private func paneHeader(title: String, subtitle: String, search: Bool = false) -> some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.system(size: 17, weight: .semibold))
        Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
      }
      Spacer(minLength: 12)

      if search {
        HStack(spacing: 5) {
          Image(systemName: "magnifyingglass")
            .font(.system(size: 11)).foregroundStyle(.secondary)
          TextField("Search settings", text: $query)
            .textFieldStyle(.plain).focused($searchFocused)
            .accessibilityLabel("Search settings")
            .font(.system(size: 12))
            .frame(width: 170)
          if !query.isEmpty {
            Button {
              query = ""
            } label: {
              Image(systemName: "xmark.circle.fill")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain).accessibilityLabel("Clear search")
          }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 10)
  }
}

// MARK: - Dropdown pane

@MainActor
private struct DropdownPane: View {
  @ObservedObject var settings: AppSettings
  @ObservedObject var engine: ToggleEngine

  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Your Menu").font(.system(size: 17, weight: .semibold))
        Text("Drag or use the arrows to reorder. Use the pin button to remove a control.")
          .font(.system(size: 11)).foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 10)
      .accessibilityAddTraits(.isHeader)

      HStack {
        Toggle("Organize by category", isOn: $settings.groupDropdown).toggleStyle(.checkbox)
        Spacer()
        Text(settings.groupDropdown ? "Category order" : "Your custom order")
          .foregroundStyle(.secondary)
      }.font(.system(size: 12)).padding(.horizontal, 18).padding(.bottom, 12)

      if settings.pinned.isEmpty {
        ContentUnavailableView(
          "Nothing pinned",
          systemImage: "pin.slash",
          description: Text("Choose controls from Everyday Settings to build your menu."))
      } else {
        List {
          ForEach(settings.pinnedSpecs) { spec in
            ToggleRow(
              spec: spec, engine: engine, settings: settings,
              showPin: true, showDetail: false, showCategory: true, showMove: true)
          }
          .onMove { settings.movePinned(from: $0, to: $1) }
        }
        .listStyle(.inset)
      }

      Divider()
      HStack {
        Button("Reset to Defaults") { settings.resetPinned() }
          .controlSize(.small)
        Spacer()
        Text("\(settings.pinned.count) pinned")
          .font(.system(size: 10.5)).foregroundStyle(.secondary)
      }
      .padding(.horizontal, 18).padding(.vertical, 10)
    }
  }
}

// MARK: - General pane

@MainActor
private struct GeneralPane: View {
  @ObservedObject var settings: AppSettings
  @ObservedObject var engine: ToggleEngine
  @ObservedObject var shortcut: GlobalShortcutController

  var body: some View {
    Form {
      Section("Menu & Startup") {
        Toggle("Launch at login", isOn: $settings.launchAtLogin)
        Toggle("Group menu controls by category", isOn: $settings.groupDropdown)
        Toggle("Show descriptions in the menu", isOn: $settings.showDescriptions)
        Toggle("Refresh controls automatically", isOn: $settings.autoRefresh)
      }

      GlobalShortcutView(controller: shortcut)

      Section {
        Toggle("Restart affected apps automatically", isOn: $settings.restartServices)
        Text(
          "Dock, Finder and Control Center only pick up some changes after a relaunch. Turning this off leaves those changes pending until you restart the app yourself. Relaunching Finder may interrupt open Finder windows."
        )
        .font(.system(size: 10.5)).foregroundStyle(.secondary)
      } header: {
        Text("Applying Changes")
      }

      Section("Permissions") {
        LabeledContent("Automation") {
          Button("Open…") {
            openPane(
              "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation"
            )
          }
        }
        Text("macOS may request permission when you first change Dark Mode or mute sound.")
          .font(.system(size: 10.5)).foregroundStyle(.secondary)
      }

      Section("Everyday Settings") {
        Text(
          "All \(Catalog.all.count) toggles start in your menu, alongside cursor and sound controls. Search finds unpinned controls too. Right-click a toggle to pin it or open System Settings."
        )
        Text(
          "Keep Awake offers 15, 30, 60, or 120 minute sessions. Right-click its row to choose a duration."
        )
        Button("Open System Settings…") { SystemSettingsLink.open() }
      }

    }
    .formStyle(.grouped)
  }

  private func openPane(_ url: String) {
    guard let u = URL(string: url) else { return }
    NSWorkspace.shared.open(u)
  }
}

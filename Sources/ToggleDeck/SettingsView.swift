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
    case .general: return "gearshape.fill"
    case .dropdown: return "menubar.arrow.down.rectangle"
    case .cursor: return "cursorarrow"
    case .sound: return "speaker.wave.2.fill"
    case .all: return "square.grid.2x2.fill"
    case .category(let c): return c.symbol
    }
  }

  /// The sidebar tile color. Panes that are not a category get muted hues
  /// of their own so they never read as one of the seven categories.
  var tint: Color {
    switch self {
    case .general: return Color(red: 0.52, green: 0.53, blue: 0.56)
    case .dropdown: return Color(red: 0.86, green: 0.24, blue: 0.24)
    case .cursor: return Color(red: 0.6, green: 0.44, blue: 0.3)
    case .sound: return Color(red: 0.33, green: 0.4, blue: 0.55)
    case .all: return Color(red: 0.8, green: 0.55, blue: 0)
    case .category(let c): return c.tint
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

  @StateObject private var router: SettingsRouter
  @ViewState<String> private var query = ""
  /// Command-F switches to a searchable pane and focuses its field in the
  /// same update, before that field exists, so the request waits here for
  /// the field to appear.
  @ViewState<Bool> private var focusSearchOnAppear = false
  @FocusState private var searchFocused: Bool

  init(
    initialSection: SettingsSection = .dropdown, router: SettingsRouter? = nil,
    engine: ToggleEngine = .shared,
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
    _router = StateObject(wrappedValue: router ?? SettingsRouter(section: initialSection))
  }

  private var section: SettingsSection {
    get { router.section }
    nonmutating set { router.request(newValue) }
  }

  var body: some View {
    NavigationSplitView {
      sidebar
    } detail: {
      VStack(spacing: 0) {
        detail
        if engine.banner != nil { FeedbackView(engine: engine).padding(16) }
      }
      .frame(minWidth: 520)
      // Stated rather than inherited so panes whose content does not fill
      // the column still sit on the window color in either appearance.
      .background(Color(nsColor: .windowBackgroundColor))
    }
    .frame(minWidth: 860, minHeight: 600)
    .task { await engine.refreshAll() }
    .onChange(of: section) { _, _ in query = "" }
    .onExitCommand { query = "" }
    .background {
      Button("") {
        switch section {
        case .all, .category: searchFocused = true
        default:
          focusSearchOnAppear = true
          section = .all
        }
      }.keyboardShortcut("f", modifiers: .command).hidden()
    }
  }

  // MARK: Sidebar

  private var sidebar: some View {
    List(selection: $router.section) {
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
    .frame(minWidth: 232)
    .safeAreaInset(edge: .bottom) {
      HStack(spacing: 6) {
        // After an update this is the only way to tell which build is running.
        Text("ToggleDeck \(AppVersion.display)")
          .accessibilityLabel("ToggleDeck version \(AppVersion.display)")
          .font(DeckStyle.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Spacer(minLength: 4)
        if engine.isRefreshing {
          ProgressView().controlSize(.small).scaleEffect(0.6)
        }
        Button {
          Task {
            await cursor.refresh()
            await pointer.refresh()
            await audio.refresh()
            await engine.refreshAll(clearError: true)
          }
        } label: {
          Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
        }
        .buttonStyle(DeckButtonStyle())
        .help("Re-read every setting")
        .accessibilityLabel("Refresh settings")
        .disabled(engine.isRefreshing)
      }
      .padding(.leading, 16).padding(.trailing, 10).padding(.vertical, 6)
    }
  }

  private func row(_ s: SettingsSection, count: Int? = nil) -> some View {
    HStack(spacing: 8) {
      IconTile(symbol: s.symbol, tint: s.tint, size: DeckStyle.smallTileSize)
      Text(s.title).lineLimit(1)
      Spacer(minLength: 4)
      if let count {
        Text("\(count)")
          .font(DeckStyle.caption)
          .monospacedDigit()
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
    case .dropdown:
      DropdownPane(settings: settings, engine: engine) { section = .all }
    case .cursor: CursorColorsPane(cursor: cursor, pointer: pointer)
    case .sound: AudioPane(audio: audio)
    case .all: listPane(Catalog.all, title: "Everyday Settings", grouped: true)
    case .category(let cat):
      listPane(Catalog.all.filter { $0.category == cat }, title: cat.rawValue, grouped: false)
    }
  }

  private func listPane(_ specs: [ToggleSpec], title: String, grouped: Bool) -> some View {
    let filtered = SettingSearch.results(in: specs, query: query)

    return VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 16) {
        PaneHeader(title: title, subtitle: "Pin controls to keep them in your menu.")
        searchField
      }
      .paneColumn()
      .padding(.top, DeckStyle.paneInset)
      .padding(.bottom, 16)

      if filtered.isEmpty {
        ContentUnavailableView {
          Label("No matching controls", systemImage: "magnifyingglass")
        } description: {
          Text("Nothing in this section matches “\(query)”.")
        } actions: {
          Button("Clear search") {
            query = ""
            searchFocused = true
          }
        }
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: DeckStyle.paneSpacing) {
            if grouped {
              // Category order, keeping search rank within each category.
              ForEach(Category.allCases) { cat in
                let rows = filtered.filter { $0.category == cat }
                if !rows.isEmpty {
                  PaneSection(title: cat.rawValue) { controlRows(rows) }
                }
              }
            } else {
              PaneSection { controlRows(filtered) }
            }
          }
          .paneColumn()
          .padding(.top, 4)
          .padding(.bottom, DeckStyle.paneInset)
        }
      }
    }
  }

  private func controlRows(_ specs: [ToggleSpec]) -> some View {
    LazyVStack(alignment: .leading, spacing: 0) {
      ForEach(Array(specs.enumerated()), id: \.element.id) { index, spec in
        if index > 0 { DeckSeparator() }
        ToggleRow(
          spec: spec, engine: engine, settings: settings,
          showPin: true, showDetail: true, showCategory: false)
      }
    }
  }

  /// The search field is drawn inline rather than via `.searchable`. That
  /// modifier installs itself in the window toolbar, and this window has no
  /// NSToolbar, so the field could silently fail to appear.
  private var searchField: some View {
    HStack(spacing: 7) {
      Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        .font(.system(size: 12, weight: .medium))
      TextField("Search this section", text: $query)
        .textFieldStyle(.plain).focused($searchFocused)
        .accessibilityLabel("Search this section")
        .onAppear {
          guard focusSearchOnAppear else { return }
          focusSearchOnAppear = false
          searchFocused = true
        }
      if !query.isEmpty {
        Button {
          query = ""
          searchFocused = true
        } label: {
          Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain).accessibilityLabel("Clear search")
      }
    }
    .font(DeckStyle.rowTitle)
    .padding(.horizontal, 10)
    .deckSearchField()
  }
}

// MARK: - Dropdown pane

@MainActor
private struct DropdownPane: View {
  @ObservedObject var settings: AppSettings
  @ObservedObject var engine: ToggleEngine
  var onAddControls: () -> Void
  @ViewState<[String]?> private var previousPins: [String]? = nil
  @ViewState<Bool> private var previousGrouping = true

  /// The leading and trailing indent AppKit gives a plain `List` row.
  private static let listIndent: CGFloat = 8

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      PaneHeader(
        title: "Your Menu",
        subtitle: "Pin your favorites. Drag or use the arrows to set a custom order."
      ) {
        Button(action: onAddControls) {
          Label("Add Controls", systemImage: "plus")
        }.controlSize(.regular)
      }
      .padding(.bottom, DeckStyle.paneSpacing)

      PaneSection {
        SettingsRow(
          title: "Order",
          caption: settings.groupDropdown
            ? "Pinned controls appear under their category."
            : "Pinned controls appear in the order below."
        ) {
          Picker("Menu order", selection: $settings.groupDropdown) {
            Text("By Category").tag(true)
            Text("Custom Order").tag(false)
          }
          .pickerStyle(.segmented).labelsHidden().fixedSize()
        }
      }
      .padding(.bottom, DeckStyle.paneSpacing)

      if settings.pinned.isEmpty {
        ContentUnavailableView {
          Label("No pinned controls", systemImage: "pin.slash")
        } description: {
          Text("Cursor and sound stay available in your menu.")
        } actions: {
          Button("Browse Controls", action: onAddControls)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .deckCard()
      } else {
        pinnedList
      }

      HStack(spacing: 8) {
        Button("Reset to Defaults") {
          previousPins = settings.pinned
          previousGrouping = settings.groupDropdown
          settings.resetPinned()
        }
        .controlSize(.small)
        .disabled(settings.pinned == Catalog.defaultPinned && settings.groupDropdown)
        if let previousPins {
          Button("Undo Reset") {
            settings.pinned = previousPins
            settings.groupDropdown = previousGrouping
            self.previousPins = nil
          }.controlSize(.small)
        }
        Spacer()
        Text("\(settings.pinned.count) pinned")
          .font(DeckStyle.caption).foregroundStyle(.secondary)
      }
      .padding(.top, 12)
    }
    .paneColumn()
    .padding(.vertical, DeckStyle.paneInset)
    .onChange(of: settings.pinned) { _, pins in
      if pins != Catalog.defaultPinned { previousPins = nil }
    }
    .onChange(of: settings.groupDropdown) { _, grouped in
      if !grouped { previousPins = nil }
    }
  }

  /// A `List` rather than a stack because `.onMove` drag reordering only
  /// works inside one. Its own chrome is cleared so it reads as a card.
  private var pinnedList: some View {
    let specs = settings.pinnedSpecs
    return List {
      ForEach(Array(specs.enumerated()), id: \.element.id) { index, spec in
        ToggleRow(
          spec: spec, engine: engine, settings: settings,
          showPin: true, showDetail: false, showCategory: true, showMove: true
        )
        // A plain List still indents each row; this lines the row up with
        // the rows of the other panes' cards.
        .padding(.horizontal, -Self.listIndent)
        .overlay(alignment: .bottom) {
          if index < specs.count - 1 { DeckSeparator() }
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
      }
      .onMove { settings.movePinned(from: $0, to: $1) }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    // AppKit rejects a zero row height; any small value lets rows size to fit.
    .environment(\.defaultMinListRowHeight, 1)
    .padding(.vertical, 4)
    .deckCard()
    .clipShape(DeckStyle.card)
  }
}

// MARK: - General pane

@MainActor
private struct GeneralPane: View {
  @ObservedObject var settings: AppSettings
  @ObservedObject var engine: ToggleEngine
  @ObservedObject var shortcut: GlobalShortcutController

  var body: some View {
    PaneScaffold {
      PaneHeader(title: "General", subtitle: "Startup, the menu, and how changes are applied.")

      PaneSection(title: "Menu & Startup") {
        toggleRow("Launch at login", isOn: $settings.launchAtLogin)
        SettingsSeparator()
        toggleRow("Group by category", isOn: $settings.groupDropdown)
        SettingsSeparator()
        toggleRow("Show descriptions in the menu", isOn: $settings.showDescriptions)
        SettingsSeparator()
        toggleRow("Refresh controls automatically", isOn: $settings.autoRefresh)
      }

      GlobalShortcutView(controller: shortcut)

      PaneSection(title: "Applying Changes") {
        toggleRow(
          "Restart affected apps automatically", isOn: $settings.restartServices,
          caption:
            "Dock, Finder and Control Center only pick up some changes after a relaunch. Turning this off leaves those changes pending until you restart the app yourself. Relaunching Finder may interrupt open Finder windows."
        )
      }

      PaneSection(title: "Permissions") {
        SettingsRow(
          title: "Automation",
          caption: "macOS may request permission when you first change Dark Mode or mute sound."
        ) {
          Button("Open…") {
            openPane(
              "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation"
            )
          }
          .accessibilityLabel("Open Automation settings")
        }
      }

      PaneSection(title: "Everyday Settings") {
        VStack(alignment: .leading, spacing: 8) {
          Text(
            "All \(Catalog.all.count) toggles start in your menu, alongside cursor and sound controls. Search finds unpinned controls too. Right-click a toggle to pin it or open System Settings."
          )
          Text(
            "Keep Awake offers 15, 30, 60, or 120 minute sessions. Right-click its row to choose a duration."
          )
          Button("Open System Settings…") { SystemSettingsLink.open() }
            .padding(.top, 2)
        }
        .font(DeckStyle.value)
        .fixedSize(horizontal: false, vertical: true)
        .settingsRowPadding()
      }
    }
  }

  private func toggleRow(_ title: String, isOn: Binding<Bool>, caption: String? = nil)
    -> some View
  {
    SettingsRow(title: title, caption: caption) {
      Toggle(title, isOn: isOn).settingsSwitch()
    }
  }

  private func openPane(_ url: String) {
    guard let u = URL(string: url) else { return }
    NSWorkspace.shared.open(u)
  }
}

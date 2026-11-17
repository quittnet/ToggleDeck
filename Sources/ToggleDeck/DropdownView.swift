import AppKit
import SwiftUI

@MainActor
struct DropdownView: View {
  @ObservedObject var engine: ToggleEngine
  @ObservedObject var settings: AppSettings
  @ObservedObject var cursor: CursorColorController
  @ObservedObject var pointer: PointerController
  @ObservedObject var audio: AudioController
  @ObservedObject var session: DropdownSession
  @ObservedObject var scenes: SceneStore
  @ViewState<String> private var query = ""
  @ViewState<ControlFilter> private var filter = ControlFilter.all
  @FocusState private var searchFocused: Bool
  @FocusState private var focusedControl: String?
  /// The row the arrow keys last moved to. A click also focuses a row, but
  /// only keyboard focus is drawn, so a clicked row doesn't stay highlighted.
  @ViewState<String?> private var keyboardFocus: String? = nil
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var onOpenSettings: () -> Void
  var onQuit: () -> Void
  var onOpenCursorSettings: () -> Void
  var onOpenSoundSettings: () -> Void
  var onOpenSceneSettings: () -> Void
  var onClose: () -> Void = {}
  var onSizeChange: (CGSize) -> Void = { _ in }
  var previewSpecs: [ToggleSpec]?
  var snapshotSearch: String?
  private let drawsOffscreen: Bool

  init(
    engine: ToggleEngine = .shared, settings: AppSettings = .shared,
    cursor: CursorColorController = .shared,
    pointer: PointerController = .shared, audio: AudioController = .shared,
    scenes: SceneStore = .shared,
    onOpenSettings: @escaping () -> Void, onQuit: @escaping () -> Void,
    onOpenCursorSettings: @escaping () -> Void = {},
    onOpenSoundSettings: @escaping () -> Void = {},
    onOpenSceneSettings: @escaping () -> Void = {}, onClose: @escaping () -> Void = {},
    onSizeChange: @escaping (CGSize) -> Void = { _ in }, previewSpecs: [ToggleSpec]? = nil,
    snapshotSearch: String? = nil, offscreen: Bool = false,
    session: DropdownSession = DropdownSession()
  ) {
    self.engine = engine
    self.settings = settings
    self.cursor = cursor
    self.pointer = pointer
    self.audio = audio
    self.scenes = scenes
    self.session = session
    self.onOpenSettings = onOpenSettings
    self.onQuit = onQuit
    self.onOpenCursorSettings = onOpenCursorSettings
    self.onOpenSoundSettings = onOpenSoundSettings
    self.onOpenSceneSettings = onOpenSceneSettings
    self.onClose = onClose
    self.onSizeChange = onSizeChange
    self.previewSpecs = previewSpecs
    self.snapshotSearch = snapshotSearch
    self.drawsOffscreen = offscreen || snapshotSearch != nil
  }

  private var showsCursor: Bool {
    filter == .all
      && (CursorPreset.matchesSearch(search)
        || cursor.palettes.savedColors.contains {
          SettingSearch.matches("Cursor Color pointer saved combination \($0.name)", query: search)
        })
  }

  private var showsSound: Bool {
    filter == .all
      && SettingSearch.matches(
        "Sound audio output speakers headphones volume device "
          + audio.outputs.map(\.name).joined(separator: " "), query: search)
  }

  private var controlCount: Int { visible.count + (showsCursor ? 1 : 0) + (showsSound ? 1 : 0) }

  private var search: String { snapshotSearch ?? query }
  private var searching: Bool { !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  private var browsing: Bool { searching || filter != .all }
  private var visible: [ToggleSpec] {
    SettingSearch.results(
      in: browsing ? Catalog.all : (previewSpecs ?? settings.pinnedSpecs), query: search
    )
    .filter { filter.includes(engine.state($0.id)) }
  }

  private var items: [DropdownLayout.Item] {
    guard settings.groupDropdown && !searching else {
      return visible.map { .row($0) } + (showsCursor ? [.cursorColor] : [])
        + (showsSound ? [.audioOutput] : [])
    }
    let groups = Dictionary(grouping: visible, by: \.category)
    return Category.allCases.flatMap { category -> [DropdownLayout.Item] in
      let rows = groups[category] ?? []
      let cursorRows: [DropdownLayout.Item] =
        category == .display && showsCursor ? [.cursorColor] : []
      let soundRows: [DropdownLayout.Item] =
        category == .connections && showsSound ? [.audioOutput] : []
      guard !rows.isEmpty || !cursorRows.isEmpty || !soundRows.isEmpty else { return [] }
      return [.header(category)] + rows.map { .row($0) } + cursorRows + soundRows
    }
  }

  /// Scenes act on the menu as a whole, so they hide while searching or filtering.
  private var showsScenes: Bool { !browsing && !scenes.scenes.isEmpty }

  private var extraChrome: CGFloat {
    (showsScenes ? DropdownChrome.sceneStrip : 0)
      + (engine.banner == nil ? 0 : DropdownChrome.bannerHeight)
      + (engine.state("keepAwake").isOn
        ? DropdownChrome.awakeStripHeight + DropdownChrome.awakeStripBottomPadding : 0)
      + (filter == .all ? 0 : DropdownChrome.filterCaptionHeight)
  }

  private var cursorAttention: Bool {
    showsCursor && (cursor.error != nil || pointer.error != nil)
  }

  private var layout: DropdownLayout.Result {
    DropdownLayout.pack(
      items, showDescriptions: settings.showDescriptions, extraChrome: extraChrome,
      cursorAttention: cursorAttention)
  }

  var body: some View {
    let packed = layout
    VStack(spacing: 0) {
      header
      if showsScenes {
        SceneStrip(
          scenes: scenes, engine: engine, snapshot: snapshotSearch != nil,
          onEdit: onOpenSceneSettings)
      }
      if controlCount == 0 {
        empty
      } else {
        columns(packed, scrolls: packed.overflowed)
      }
      if engine.state("keepAwake").isOn { awakeStatus }
      if engine.banner != nil {
        if snapshotSearch != nil {
          FeedbackView(engine: engine).padding(.horizontal, DeckStyle.panelInset)
            .padding(.bottom, 10)
            .frame(height: DropdownChrome.bannerHeight, alignment: .top)
        } else {
          ScrollView {
            FeedbackView(engine: engine).padding(.horizontal, DeckStyle.panelInset)
              .padding(.bottom, 10)
          }
          .frame(height: DropdownChrome.bannerHeight)
        }
      }
      footer
    }
    .frame(width: packed.width)
    // Both PNG exporters draw without the live popover's backdrop.
    .background(drawsOffscreen || reduceTransparency ? DeckStyle.panelFallback : .clear)
    .background {
      GeometryReader { geometry in
        Color.clear.task(id: geometry.size) { onSizeChange(geometry.size) }
      }
    }
    .task {
      await cursor.refresh(clearError: false)
      await pointer.refresh(clearError: false)
      await audio.refresh(clearError: false)
      await engine.refreshAll()
    }
    .onAppear { searchFocused = true }
    // The view outlives each popover, so a new open starts from the menu
    // rather than the last search or filter.
    .onChange(of: session.openCount) { _, _ in
      guard snapshotSearch == nil else { return }
      query = ""
      filter = .all
      focusedControl = nil
      searchFocused = true
    }
    .onChange(of: searchFocused) { _, focused in if focused { focusedControl = nil } }
    .onChange(of: query) { _, _ in focusedControl = nil }
    .onChange(of: filter) { _, _ in focusedControl = nil }
    .onExitCommand {
      if browsing {
        query = ""
        filter = .all
        searchFocused = true
      } else {
        onClose()
      }
    }
    .onMoveCommand { direction in
      switch direction {
      case .down: moveFocus(.down)
      case .up:
        if DropdownNavigation.isFirst(focusedControl, in: navigationColumns) {
          searchFocused = true
        } else {
          moveFocus(.up)
        }
      case .left: if focusedControl != nil { moveFocus(.left) }
      case .right: if focusedControl != nil { moveFocus(.right) }
      @unknown default: break
      }
    }
  }

  private var header: some View {
    VStack(spacing: 0) {
      HStack(spacing: 6) {
        searchField
        refreshButton
        moreMenu
      }
      // Held to the height the layout engine counts, whatever the menu
      // buttons would take on their own.
      .frame(height: DropdownChrome.searchHeight)
      .padding(.top, DropdownChrome.searchTopPadding)
      .padding(.bottom, DropdownChrome.searchBottomPadding)
      if filter != .all {
        HStack {
          Text("Showing \(filter.rawValue.lowercased()) controls").font(DeckStyle.caption)
            .foregroundStyle(.secondary)
          Spacer()
          Button("Clear filter") { filter = .all }.buttonStyle(.link).font(DeckStyle.caption)
        }
        .padding(.horizontal, 4)
        .frame(height: DropdownChrome.filterCaptionHeight)
      }
    }
    .padding(.horizontal, DeckStyle.panelInset)
  }

  private var searchField: some View {
    HStack(spacing: 6) {
      Button {
        searchFocused = true
      } label: {
        Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium))
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain).keyboardShortcut("f", modifiers: .command).accessibilityLabel(
        "Focus search")
      if snapshotSearch != nil {
        Text(search.isEmpty ? "Search all Mac controls" : search)
          .foregroundStyle(search.isEmpty ? .secondary : .primary)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        TextField("Search all Mac controls", text: $query)
          .textFieldStyle(.plain).focused($searchFocused).accessibilityLabel(
            "Search all Mac controls"
          )
          .onSubmit { moveFocus(.down) }
          // The field editor consumes Down before .onMoveCommand sees it,
          // so the list was reachable from search only with Return.
          .onKeyPress(.downArrow) {
            guard navigationColumns.contains(where: { !$0.isEmpty }) else { return .ignored }
            moveFocus(.down)
            return .handled
          }
      }
      if searching {
        Button {
          query = ""
          searchFocused = true
        } label: {
          Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
        }.buttonStyle(.plain).accessibilityLabel("Clear search")
      }
      filterMenu
    }
    .font(DeckStyle.rowTitle)
    .padding(.leading, 12).padding(.trailing, 5)
    .deckSearchField(nativeGlass: !drawsOffscreen)
  }

  @ViewBuilder
  private var filterMenu: some View {
    let symbol =
      filter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill"
    let label = Image(systemName: symbol).font(.system(size: 12, weight: .medium))
      .foregroundStyle(filter == .all ? Color.secondary : Color.accentColor)
      .frame(width: 24, height: 24)
    if snapshotSearch != nil {
      label
    } else {
      Menu {
        Picker("Show controls", selection: $filter) {
          ForEach(ControlFilter.allCases) { Text($0.rawValue).tag($0) }
        }
      } label: {
        label
      }
      .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
      .help("Filter all controls by state").accessibilityLabel(
        "Filter controls: \(filter.rawValue)")
    }
  }

  private var refreshButton: some View {
    Button {
      Task {
        await cursor.refresh()
        await pointer.refresh()
        await audio.refresh()
        await engine.refreshAll(clearError: true)
      }
    } label: {
      if engine.isRefreshing && snapshotSearch == nil {
        ProgressView().controlSize(.small).frame(
          width: DeckStyle.searchFieldHeight, height: DeckStyle.searchFieldHeight)
      } else {
        Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .medium))
          .foregroundStyle(.secondary).frame(
            width: DeckStyle.searchFieldHeight, height: DeckStyle.searchFieldHeight)
      }
    }
    .buttonStyle(DeckButtonStyle()).clipShape(Capsule()).deckCapsule(nativeGlass: !drawsOffscreen)
    .disabled(engine.isRefreshing)
    .help("Refresh settings (Command-R)").accessibilityLabel("Refresh settings")
    .keyboardShortcut("r", modifiers: .command)
  }

  @ViewBuilder
  private var moreMenu: some View {
    let label = Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium))
      .foregroundStyle(.secondary).frame(
        width: DeckStyle.searchFieldHeight, height: DeckStyle.searchFieldHeight
      )
      .deckCapsule(nativeGlass: !drawsOffscreen)
    if snapshotSearch != nil {
      label
    } else {
      Menu {
        Button("Customize Menu…", action: onOpenSettings).keyboardShortcut(
          ",", modifiers: .command)
        Button(
          scenes.scenes.isEmpty ? "Create a Scene…" : "Edit Scenes…", action: onOpenSceneSettings)
        Toggle("Show Descriptions", isOn: $settings.showDescriptions)
        Toggle("Group by category", isOn: $settings.groupDropdown)
        Menu("Keep Awake") { AwakeDurationActions(engine: engine) }
        Button("Open System Settings…") { SystemSettingsLink.open() }
        Divider()
        Button("Quit ToggleDeck", action: onQuit)
      } label: {
        label
      }
      .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
      .accessibilityLabel("More options")
    }
  }

  @ViewBuilder
  private func columns(_ packed: DropdownLayout.Result, scrolls: Bool) -> some View {
    let stack = HStack(alignment: .top, spacing: DeckStyle.columnSpacing) {
      ForEach(Array(packed.columns.enumerated()), id: \.offset) { _, column in
        columnView(column).frame(width: packed.columnWidth)
      }
    }
    .padding(.horizontal, DeckStyle.panelInset)
    .padding(.top, DropdownChrome.columnsTopPadding)
    .padding(.bottom, DropdownChrome.columnsBottomPadding)
    if scrolls {
      ScrollViewReader { proxy in
        ScrollView { stack }
          .frame(maxHeight: DropdownLayout.availableHeight(metrics))
          .onChange(of: focusedControl) { _, id in
            if let id { proxy.scrollTo(id, anchor: .center) }
          }
      }
    } else {
      stack.fixedSize(horizontal: false, vertical: true)
    }
  }

  /// A run of rows drawn as one card, under its category label when grouped.
  private struct Section: Identifiable {
    var category: Category?
    var rows: [DropdownLayout.Item]
    var id: String { category.map { "h:\($0.rawValue)" } ?? rows.first?.id ?? "" }
  }

  private func sections(_ column: [DropdownLayout.Item]) -> [Section] {
    var result: [Section] = []
    for item in column {
      if case .header(let category) = item {
        result.append(Section(category: category, rows: []))
      } else if result.isEmpty {
        result.append(Section(category: nil, rows: [item]))
      } else {
        result[result.count - 1].rows.append(item)
      }
    }
    return result
  }

  /// Heights here are exactly `DropdownLayout.height`: labels take
  /// `headerHeight`, rows their own fixed height, and separators are
  /// overlays that add nothing.
  private func columnView(_ column: [DropdownLayout.Item]) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(sections(column)) { section in
        if let category = section.category { sectionLabel(category) }
        if !section.rows.isEmpty {
          VStack(spacing: 0) {
            ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, item in
              row(item)
                .overlay(alignment: .top) { if index > 0 { DeckSeparator() } }
            }
          }
          .deckCard(nativeGlass: !drawsOffscreen)
        }
      }
    }
  }

  private func sectionLabel(_ category: Category) -> some View {
    HStack(alignment: .lastTextBaseline) {
      DeckSectionLabel(title: category.rawValue)
      Spacer()
      if category == .power {
        let timer = Label("Timer", systemImage: "timer").font(DeckStyle.caption)
          .foregroundStyle(.secondary)
        if snapshotSearch != nil {
          timer
        } else {
          Menu {
            AwakeDurationActions(engine: engine)
          } label: {
            timer
          }
          .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
          // The AppKit-backed menu button ignores its label's font, so the
          // size is set on the control itself.
          .font(DeckStyle.caption).controlSize(.small).foregroundStyle(.secondary)
          .help("Start a timed Keep Awake session").accessibilityLabel("Keep Awake timer")
        }
      }
    }
    .padding(.horizontal, DeckStyle.rowInset).padding(.bottom, 6)
    .frame(height: DropdownLayout.Metrics(showDescriptions: false).headerHeight, alignment: .bottom)
  }

  @ViewBuilder
  private func row(_ item: DropdownLayout.Item) -> some View {
    switch item {
    case .cursorColor:
      CursorColorMenu(
        cursor: cursor, pointer: pointer, onCustom: onOpenCursorSettings,
        snapshot: snapshotSearch != nil, isFocused: showsFocus("cursorColor")
      )
      .focused($focusedControl, equals: "cursorColor").id("cursorColor")
    case .audioOutput:
      AudioMenuRow(
        audio: audio, snapshot: snapshotSearch != nil,
        onOpenSettings: onOpenSoundSettings, isFocused: showsFocus("audioOutput")
      )
      .focused($focusedControl, equals: "audioOutput").id("audioOutput")
    case .header:
      EmptyView()
    case .row(let spec):
      DropdownControlRow(
        spec: spec, state: engine.state(spec.id),
        showDescriptions: settings.showDescriptions, isFocused: showsFocus(spec.id),
        snapshot: snapshotSearch != nil, trailingReserve: browsing ? pinWidth : 0
      ) {
        Task { await engine.set(spec.id, on: !engine.state(spec.id).isOn) }
      }
      .focused($focusedControl, equals: spec.id)
      .contextMenu { ControlContextMenu(spec: spec, engine: engine, settings: settings) }
      .overlay(alignment: .trailing) {
        if browsing { pinButton(spec).padding(.trailing, 6) }
      }
      .id(spec.id)
    }
  }

  private var pinWidth: CGFloat { 26 }

  private func pinButton(_ spec: ToggleSpec) -> some View {
    let pinned = settings.isPinned(spec.id)
    return Button {
      settings.togglePin(spec.id)
    } label: {
      Image(systemName: pinned ? "pin.fill" : "pin")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(pinned ? Color.accentColor : Color.secondary)
        .frame(width: 24, height: 24)
    }
    .buttonStyle(DeckButtonStyle())
    .help(pinned ? "Remove from Menu" : "Add to Menu")
    .accessibilityLabel("\(pinned ? "Unpin" : "Pin") \(spec.menuTitle)")
  }

  private var metrics: DropdownLayout.Metrics {
    var value = DropdownLayout.Metrics(showDescriptions: settings.showDescriptions)
    value.chromeHeight += extraChrome
    return value
  }

  private var onCount: Int {
    visible.filter {
      let state = engine.state($0.id)
      return state.supported && !state.stale && state.isOn
    }.count
  }

  private var footer: some View {
    HStack(spacing: 6) {
      if engine.isRefreshing {
        Text("Reading controls…")
      } else {
        Text(
          browsing
            ? "\(controlCount) \(controlCount == 1 ? "result" : "results")"
            : "\(controlCount) controls")
        if !browsing {
          Text("·").accessibilityHidden(true)
          Text("\(onCount) on")
        }
      }
      Spacer()
      Button(action: onOpenSettings) {
        Label("Customize", systemImage: "slider.horizontal.3")
          .font(.system(size: 12, weight: .medium))
          .padding(.horizontal, 11).frame(height: 26)
      }
      .buttonStyle(DeckButtonStyle()).clipShape(Capsule()).deckCapsule(nativeGlass: !drawsOffscreen)
      .help("Choose and reorder menu controls (Command-comma)")
      .keyboardShortcut(",", modifiers: .command)
    }
    .font(DeckStyle.caption).foregroundStyle(.secondary)
    // Count text lines up with the section labels, the button with the cards.
    .padding(.leading, DeckStyle.panelInset + DeckStyle.rowInset)
    .padding(.trailing, DeckStyle.panelInset)
    .frame(height: DropdownChrome.footerHeight)
    // An overlay, so the hairline adds no height to the chrome sum.
    .overlay(alignment: .top) {
      Rectangle().fill(DeckStyle.separator).frame(height: 1).accessibilityHidden(true)
    }
  }

  private var awakeStatus: some View {
    let tint = Category.power.tint
    return HStack(spacing: 8) {
      IconTile(symbol: "cup.and.saucer.fill", tint: tint, size: DeckStyle.smallTileSize)
      Group {
        if let until = engine.keepAwakeUntil {
          TimelineView(.periodic(from: .now, by: 1)) { context in
            let minutes = max(0, Int(ceil(until.timeIntervalSince(context.date) / 60)))
            Text("Awake · \(minutes) min remaining")
          }
        } else {
          Text("Awake until quit")
        }
      }
      .font(.system(size: 12, weight: .medium))
      Spacer()
      Group {
        if snapshotSearch != nil {
          Text("Duration").foregroundStyle(.secondary)
        } else {
          Menu("Duration") {
            ForEach([15, 30, 60, 120], id: \.self) { minutes in
              Button("\(minutes) minutes") {
                Task { await engine.keepAwake(for: Double(minutes) * 60) }
              }
            }
            Button("Until quit") { Task { await engine.keepAwake(for: nil) } }
          }.menuStyle(.borderlessButton).controlSize(.small).fixedSize()
        }
        Button {
          Task { await engine.set("keepAwake", on: false) }
        } label: {
          Text("Stop").padding(.horizontal, 8).frame(height: 22)
        }
        .buttonStyle(DeckButtonStyle()).disabled(engine.state("keepAwake").busy)
      }
      .font(DeckStyle.caption)
    }
    .padding(.leading, 7).padding(.trailing, 6)
    .frame(height: DropdownChrome.awakeStripHeight)
    .background(tint.opacity(0.12), in: DeckStyle.card)
    .overlay { DeckStyle.card.strokeBorder(tint.opacity(0.22), lineWidth: 1) }
    .padding(.horizontal, DeckStyle.panelInset)
    .padding(.bottom, DropdownChrome.awakeStripBottomPadding)
  }

  private var empty: some View {
    VStack(spacing: 8) {
      IconTile(
        symbol: browsing ? "magnifyingglass" : "pin.slash", isLit: false, size: 40)
      Text(browsing ? "No matching controls" : "Your menu is empty")
        .font(.system(size: 13, weight: .semibold))
      Text(
        browsing
          ? "Try Wi-Fi, Dock, or sound, or clear the filter."
          : "Add your most-used controls from Customize."
      )
      .font(DeckStyle.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
      // SwiftUI-drawn, so the button also appears in ImageRenderer snapshots.
      Button {
        if browsing {
          query = ""
          filter = .all
          searchFocused = true
        } else {
          onOpenSettings()
        }
      } label: {
        Text(browsing ? "Clear search and filters" : "Customize Menu…")
          .font(DeckStyle.caption.weight(.medium)).foregroundStyle(Color.accentColor)
          .padding(.horizontal, 10).frame(height: 24)
          .background(DeckStyle.quietFill, in: DeckStyle.row)
      }
      .buttonStyle(DeckButtonStyle()).padding(.top, 4)
    }
    .padding(20).frame(maxWidth: .infinity).frame(minHeight: 176)
    .deckCard(nativeGlass: !drawsOffscreen)
    .padding(.horizontal, DeckStyle.panelInset)
    .padding(.top, DropdownChrome.columnsTopPadding)
    .padding(.bottom, DropdownChrome.columnsBottomPadding)
  }

  private var navigationColumns: [[String]] {
    layout.columns.map { column in
      column.compactMap { item -> String? in
        if case .cursorColor = item { return cursor.isApplying ? nil : "cursorColor" }
        if case .audioOutput = item { return audio.isApplying ? nil : "audioOutput" }
        guard case .row(let spec) = item else { return nil }
        return DropdownNavigation.isNavigable(engine.state(spec.id)) ? spec.id : nil
      }
    }
  }

  private func moveFocus(_ direction: DropdownNavigation.Direction) {
    focusedControl = DropdownNavigation.target(
      in: navigationColumns, current: focusedControl, direction: direction)
    keyboardFocus = focusedControl
    if focusedControl != nil { searchFocused = false }
  }

  private func showsFocus(_ id: String) -> Bool {
    focusedControl == id && keyboardFocus == id
  }
}

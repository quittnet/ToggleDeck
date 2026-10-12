import AppKit
import SwiftUI

@MainActor
struct DropdownView: View {
  @ObservedObject var engine: ToggleEngine
  @ObservedObject var settings: AppSettings
  @ObservedObject var cursor: CursorColorController
  @ObservedObject var pointer: PointerController
  @ObservedObject var audio: AudioController
  @ViewState<String> private var query = ""
  @ViewState<ControlFilter> private var filter = ControlFilter.all
  @FocusState private var searchFocused: Bool
  @FocusState private var focusedControl: String?

  var onOpenSettings: () -> Void
  var onQuit: () -> Void
  var onOpenCursorSettings: () -> Void
  var onOpenSoundSettings: () -> Void
  var onClose: () -> Void = {}
  var onSizeChange: (CGSize) -> Void = { _ in }
  var previewSpecs: [ToggleSpec]?
  var snapshotSearch: String?

  init(
    engine: ToggleEngine = .shared, settings: AppSettings = .shared,
    cursor: CursorColorController = .shared,
    pointer: PointerController = .shared, audio: AudioController = .shared,
    onOpenSettings: @escaping () -> Void, onQuit: @escaping () -> Void,
    onOpenCursorSettings: @escaping () -> Void = {},
    onOpenSoundSettings: @escaping () -> Void = {}, onClose: @escaping () -> Void = {},
    onSizeChange: @escaping (CGSize) -> Void = { _ in }, previewSpecs: [ToggleSpec]? = nil,
    snapshotSearch: String? = nil
  ) {
    self.engine = engine
    self.settings = settings
    self.cursor = cursor
    self.pointer = pointer
    self.audio = audio
    self.onOpenSettings = onOpenSettings
    self.onQuit = onQuit
    self.onOpenCursorSettings = onOpenCursorSettings
    self.onOpenSoundSettings = onOpenSoundSettings
    self.onClose = onClose
    self.onSizeChange = onSizeChange
    self.previewSpecs = previewSpecs
    self.snapshotSearch = snapshotSearch
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

  private var extraChrome: CGFloat {
    (engine.banner == nil ? 0 : 120) + (engine.state("keepAwake").isOn ? 38 : 0)
      + (filter == .all ? 0 : 24)
  }

  private var layout: DropdownLayout.Result {
    DropdownLayout.pack(
      items, showDescriptions: settings.showDescriptions, extraChrome: extraChrome)
  }

  var body: some View {
    let packed = layout
    VStack(spacing: 0) {
      header
      Divider().padding(.horizontal, 16)
      if controlCount == 0 {
        empty
      } else {
        HStack(alignment: .top, spacing: 16) {
          ForEach(Array(packed.columns.enumerated()), id: \.offset) { _, column in
            columnView(column, scrolls: packed.overflowed).frame(width: packed.columnWidth)
          }
        }
        .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 12)
        .fixedSize(horizontal: false, vertical: true)
      }
      if engine.state("keepAwake").isOn { awakeStatus }
      if engine.banner != nil {
        if snapshotSearch != nil {
          FeedbackView(engine: engine).padding(.horizontal, 16).padding(.bottom, 10)
            .frame(height: 120, alignment: .top)
        } else {
          ScrollView { FeedbackView(engine: engine).padding(.horizontal, 16).padding(.bottom, 10) }
            .frame(height: 120)
        }
      }
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
    .task {
      await cursor.refresh(clearError: false)
      await pointer.refresh(clearError: false)
      await audio.refresh(clearError: false)
      await engine.refreshAll()
    }
    .onAppear { searchFocused = true }
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
      case .up: moveFocus(.up)
      case .left: if focusedControl != nil { moveFocus(.left) }
      case .right: if focusedControl != nil { moveFocus(.right) }
      @unknown default: break
      }
    }
  }

  private var header: some View {
    VStack(spacing: 12) {
      HStack(spacing: 9) {
        Image(nsImage: SwitchGlyph.statusItemImage())
          .frame(width: 24, height: 24).accessibilityHidden(true)
        Text("ToggleDeck").font(.system(size: 15, weight: .semibold))
        Spacer()
        Button {
          Task {
            await cursor.refresh()
            await pointer.refresh()
            await audio.refresh()
            await engine.refreshAll()
          }
        } label: {
          if engine.isRefreshing && snapshotSearch == nil {
            ProgressView().controlSize(.small).frame(width: 28, height: 28)
          } else {
            Image(systemName: "arrow.clockwise").frame(width: 28, height: 28)
          }
        }
        .buttonStyle(DeckButtonStyle()).disabled(engine.isRefreshing)
        .help("Refresh settings (Command-R)").accessibilityLabel("Refresh settings")
        .keyboardShortcut("r", modifiers: .command)
        if snapshotSearch != nil {
          Image(systemName: "ellipsis").frame(width: 28, height: 28)
        } else {
          Menu {
            Button("Customize Menu…", action: onOpenSettings).keyboardShortcut(
              ",", modifiers: .command)
            Toggle("Show Descriptions", isOn: $settings.showDescriptions)
            Toggle("Group by Category", isOn: $settings.groupDropdown)
            Menu("Keep Awake") { AwakeDurationActions(engine: engine) }
            Button("Open System Settings…") { SystemSettingsLink.open() }
            Divider()
            Button("Quit ToggleDeck", action: onQuit).keyboardShortcut("q", modifiers: .command)
          } label: {
            Image(systemName: "ellipsis").frame(width: 28, height: 28)
          }
          .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
          .accessibilityLabel("More options")
        }
        Button(action: onClose) { Image(systemName: "xmark").frame(width: 28, height: 28) }
          .buttonStyle(DeckButtonStyle()).help("Close menu (Escape)").accessibilityLabel(
            "Close menu")
      }
      HStack(spacing: 8) {
        Button {
          searchFocused = true
        } label: {
          Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
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
        }
        if browsing {
          Button {
            query = ""
            filter = .all
            searchFocused = true
          } label: {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
          }.buttonStyle(.plain).accessibilityLabel("Clear search and filters")
        }
        if snapshotSearch != nil {
          Image(systemName: "line.3.horizontal.decrease").foregroundStyle(.secondary)
        } else {
          Menu {
            Picker("Show controls", selection: $filter) {
              ForEach(ControlFilter.allCases) { Text($0.rawValue).tag($0) }
            }
          } label: {
            Image(
              systemName: filter == .all
                ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill"
            )
            .foregroundStyle(filter == .all ? Color.secondary : Color.accentColor).frame(
              width: 22, height: 24)
          }
          .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
          .help("Filter all controls by state").accessibilityLabel(
            "Filter controls: \(filter.rawValue)")
        }
      }
      .font(.system(size: 13)).padding(.horizontal, 10).frame(height: 34)
      .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8).strokeBorder(
          searchFocused ? Color.accentColor.opacity(0.75) : Color.primary.opacity(0.12),
          lineWidth: 1)
      }
      if filter != .all {
        HStack {
          Text("Showing \(filter.rawValue.lowercased()) controls").font(.system(size: 11))
            .foregroundStyle(.secondary)
          Spacer()
          Button("Clear filter") { filter = .all }.buttonStyle(.link).font(.system(size: 11))
        }
      }
    }
    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
  }

  @ViewBuilder
  private func columnView(_ column: [DropdownLayout.Item], scrolls: Bool) -> some View {
    let content = VStack(alignment: .leading, spacing: 0) {
      ForEach(column) { item in
        switch item {
        case .cursorColor:
          CursorColorMenu(
            cursor: cursor, pointer: pointer, onCustom: onOpenCursorSettings,
            snapshot: snapshotSearch != nil
          )
          .focused($focusedControl, equals: "cursorColor").id("cursorColor")
        case .audioOutput:
          AudioMenuRow(
            audio: audio, snapshot: snapshotSearch != nil,
            onOpenSettings: onOpenSoundSettings
          )
          .focused($focusedControl, equals: "audioOutput").id("audioOutput")
        case .header(let category):
          HStack {
            Text(category.rawValue).font(.system(size: 11, weight: .semibold))
              .accessibilityAddTraits(.isHeader)
            Spacer()
            if category == .power {
              if snapshotSearch != nil {
                Label("Timer", systemImage: "timer").font(.system(size: 11))
              } else {
                Menu {
                  AwakeDurationActions(engine: engine)
                } label: {
                  Label("Timer", systemImage: "timer").font(.system(size: 11))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Start a timed Keep Awake session").accessibilityLabel("Keep Awake timer")
              }
            }
          }.foregroundStyle(.secondary).padding(.horizontal, 10)
            .padding(.bottom, 4).frame(height: 30, alignment: .bottom)
        case .row(let spec):
          HStack(spacing: 0) {
            DropdownControlRow(
              spec: spec, state: engine.state(spec.id),
              showDescriptions: settings.showDescriptions, isFocused: focusedControl == spec.id,
              snapshot: snapshotSearch != nil
            ) {
              Task { await engine.set(spec.id, on: !engine.state(spec.id).isOn) }
            }
            .focused($focusedControl, equals: spec.id)
            .contextMenu { ControlContextMenu(spec: spec, engine: engine, settings: settings) }
            if browsing {
              Button {
                settings.togglePin(spec.id)
              } label: {
                Image(systemName: settings.isPinned(spec.id) ? "pin.fill" : "pin")
                  .font(.system(size: 11)).foregroundStyle(
                    settings.isPinned(spec.id) ? Color.accentColor : Color.secondary
                  )
                  .frame(width: 24, height: 28)
              }
              .buttonStyle(DeckButtonStyle())
              .help(settings.isPinned(spec.id) ? "Remove from Menu" : "Add to Menu")
              .accessibilityLabel(
                "\(settings.isPinned(spec.id) ? "Unpin" : "Pin") \(spec.menuTitle)")
            }
          }.id(spec.id)
        }
      }
    }
    if scrolls {
      ScrollViewReader { proxy in
        ScrollView { content }
          .frame(maxHeight: DropdownLayout.availableHeight(metrics))
          .onChange(of: focusedControl) { _, id in if let id { proxy.scrollTo(id, anchor: .center) }
          }
      }
    } else {
      content
    }
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
    HStack(spacing: 8) {
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
        Label("Customize", systemImage: "slider.horizontal.3").font(
          .system(size: 12, weight: .medium))
      }
      .buttonStyle(DeckButtonStyle()).help("Choose and reorder menu controls (Command-comma)")
      .keyboardShortcut(",", modifiers: .command)
    }
    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 18).frame(height: 44)
  }

  private var awakeStatus: some View {
    HStack(spacing: 8) {
      Image(systemName: "cup.and.saucer.fill").foregroundStyle(Color.accentColor)
      if let until = engine.keepAwakeUntil {
        TimelineView(.periodic(from: .now, by: 1)) { context in
          let minutes = max(0, Int(ceil(until.timeIntervalSince(context.date) / 60)))
          Text("Awake · \(minutes) min remaining")
        }
      } else {
        Text("Awake until quit")
      }
      Spacer()
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
        }.menuStyle(.borderlessButton).fixedSize()
      }
      Button("Stop") { Task { await engine.set("keepAwake", on: false) } }
        .buttonStyle(DeckButtonStyle()).disabled(engine.state("keepAwake").busy)
    }
    .font(.system(size: 11)).padding(.horizontal, 18).frame(height: 38)
    .background(Color.accentColor.opacity(0.07))
  }

  private var empty: some View {
    VStack(spacing: 10) {
      Image(systemName: browsing ? "magnifyingglass" : "pin.slash").font(.system(size: 24))
        .foregroundStyle(.secondary)
      Text(browsing ? "No matching controls" : "Your menu is empty").font(
        .system(size: 14, weight: .medium))
      Text(
        browsing
          ? "Try Wi-Fi, Dock, or sound, or clear the filter."
          : "Add your most-used controls from Customize."
      )
      .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
      Button(browsing ? "Clear search and filters" : "Customize Menu…") {
        if browsing {
          query = ""
          filter = .all
          searchFocused = true
        } else {
          onOpenSettings()
        }
      }.controlSize(.small)
    }.padding(24).frame(maxWidth: .infinity).frame(minHeight: 200)
  }

  private func moveFocus(_ direction: DropdownNavigation.Direction) {
    let columns = layout.columns.map { column in
      column.compactMap { item -> String? in
        if case .cursorColor = item { return cursor.isApplying ? nil : "cursorColor" }
        if case .audioOutput = item { return audio.isApplying ? nil : "audioOutput" }
        guard case .row(let spec) = item else { return nil }
        let state = engine.state(spec.id)
        return state.supported && !state.stale && !state.busy ? spec.id : nil
      }
    }
    focusedControl = DropdownNavigation.target(
      in: columns, current: focusedControl, direction: direction)
    if focusedControl != nil { searchFocused = false }
  }
}

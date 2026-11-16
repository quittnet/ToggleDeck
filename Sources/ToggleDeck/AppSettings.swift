import AppKit
import Foundation

/// ToggleDeck's own preferences, distinct from the system settings it controls.
@MainActor
final class AppSettings: ObservableObject {
  static let shared = AppSettings()

  private let store: UserDefaults?
  private let managesLoginItem: Bool
  /// Set while the observer is writing a read-back correction, so that write
  /// does not re-enter the observer and rewrite the LaunchAgent a second time.
  private var applyingLoginItem = false

  /// IDs shown in the menu bar dropdown, in display order.
  @Published var pinned: [String] { didSet { store?.set(pinned, forKey: "pinned") } }
  /// Restart Dock/Finder/Control Center automatically after a write that needs it.
  @Published var restartServices: Bool {
    didSet { store?.set(restartServices, forKey: "restartServices") }
  }
  /// Show the one-line explanation under each switch in the dropdown.
  @Published var showDescriptions: Bool {
    didSet { store?.set(showDescriptions, forKey: "showDescriptions") }
  }
  /// Group the dropdown by category instead of showing one flat list.
  @Published var groupDropdown: Bool {
    didSet { store?.set(groupDropdown, forKey: "groupDropdown") }
  }
  /// Re-read every setting on a timer while a window is open.
  @Published var autoRefresh: Bool { didSet { store?.set(autoRefresh, forKey: "autoRefresh") } }

  @Published var launchAtLogin: Bool {
    didSet {
      guard managesLoginItem, !applyingLoginItem else { return }
      // No early-out on `launchAtLogin != LoginItem.isEnabled`. That test
      // only asks whether the plist file exists, so an agent left pointing
      // at a stale binary path could never be rewritten — login would keep
      // starting an old build while the switch read ON. Enabling always
      // rewrites, and the result is read back so the UI cannot claim a
      // write that silently failed.
      LoginItem.set(launchAtLogin)
      let actual = LoginItem.isEnabled
      guard actual != launchAtLogin else { return }
      applyingLoginItem = true
      launchAtLogin = actual
      applyingLoginItem = false
    }
  }

  init(store: UserDefaults? = UserDefaults.standard, manageLoginItem: Bool = true) {
    self.store = store
    managesLoginItem = manageLoginItem && store != nil
    // A pinned list with no version key predates versioning: treat it as oldest.
    let savedVersion = store?.object(forKey: Self.pinnedSchemaVersionKey) as? Int ?? 0
    pinned = Self.migratedPins(
      store?.array(forKey: "pinned") as? [String], schemaVersion: savedVersion)
    restartServices = store?.object(forKey: "restartServices") as? Bool ?? true
    showDescriptions = store?.object(forKey: "showDescriptions") as? Bool ?? false
    groupDropdown = store?.object(forKey: "groupDropdown") as? Bool ?? true
    autoRefresh = store?.object(forKey: "autoRefresh") as? Bool ?? true
    launchAtLogin = managesLoginItem && LoginItem.isEnabled

    store?.set(pinned, forKey: "pinned")
    store?.set(Self.currentPinnedSchemaVersion, forKey: Self.pinnedSchemaVersionKey)
  }

  /// Purely in-memory preferences for previews, with no LaunchAgent access.
  static func preview() -> AppSettings { AppSettings(store: nil, manageLoginItem: false) }

  static let pinnedSchemaVersionKey = "pinnedSchemaVersion"

  /// Version of the saved `pinned` list's relationship to the default menu.
  /// When a release adds a control to `Catalog.defaultPinned`, bump this and add
  /// an upgrade step in `migratedPins` guarded by `schemaVersion < N`. Only lists
  /// still equal to an older default may be replaced; never match old defaults
  /// unconditionally, or controls the user removed come back on every launch.
  nonisolated static let currentPinnedSchemaVersion = 1

  /// `schemaVersion` 0 means legacy data saved before the version key existed.
  nonisolated static func migratedPins(_ saved: [String]?, schemaVersion: Int = 0) -> [String] {
    guard let saved else { return Catalog.defaultPinned }
    if schemaVersion < 1 {
      if saved == Catalog.versionTwoDefaultPinned || saved == Catalog.version26DefaultPinned {
        return Catalog.defaultPinned
      }
      if Array(saved.prefix(Catalog.previousDefaultPinned.count)) == Catalog.previousDefaultPinned {
        let extras = saved.dropFirst(Catalog.previousDefaultPinned.count)
        var seen = Set(Catalog.defaultPinned)
        return Catalog.defaultPinned
          + extras.filter { Catalog.byID[$0] != nil && seen.insert($0).inserted }
      }
    }
    var seen = Set<String>()
    let retained = saved.filter { Catalog.byID[$0] != nil && seen.insert($0).inserted }
    // Preserve intentionally empty menus, but replace menus containing only retired IDs.
    return retained.isEmpty && !saved.isEmpty ? Catalog.defaultPinned : retained
  }

  var pinnedSpecs: [ToggleSpec] { pinned.compactMap { Catalog.byID[$0] } }

  func isPinned(_ id: String) -> Bool { pinned.contains(id) }

  func togglePin(_ id: String) {
    guard Catalog.byID[id] != nil else { return }
    if let idx = pinned.firstIndex(of: id) {
      pinned.remove(at: idx)
    } else {
      pinned.append(id)
    }
  }

  func movePinned(from source: IndexSet, to destination: Int) {
    pinned.move(fromOffsets: source, toOffset: destination)
    // Category grouping deliberately imposes category order. A custom move
    // switches to the saved order so the menu follows what the user arranged.
    groupDropdown = false
  }

  func movePin(_ id: String, by offset: Int) {
    guard let index = pinned.firstIndex(of: id) else { return }
    let target = index + offset
    guard pinned.indices.contains(target) else { return }
    pinned.swapAt(index, target)
    groupDropdown = false
  }

  func resetPinned() {
    pinned = Catalog.defaultPinned
    groupDropdown = true
  }
}

// MARK: - Launch at login

/// Managed as a LaunchAgent rather than through SMAppService: the bundle is
/// ad-hoc signed, and SMAppService rejects registrations it cannot attribute to
/// a stable Developer ID.
///
/// The app never calls `launchctl`. launchd reads `~/Library/LaunchAgents` at
/// login, so the plist's presence is the whole setting. Loading it into the
/// current session breaks the app both ways:
/// - `bootstrap` of a RunAtLoad job makes launchd start a second copy of the
///   executable immediately (launchd bypasses LaunchServices), leaving two menu
///   bar icons and a global-shortcut conflict.
/// - `bootout` of the job unloads it, and launchd terminates its process. When
///   the app was started at login, the running app is that job, so unticking
///   the switch would quit it.
enum LoginItem {
  static let label = "com.user.toggledeck"

  /// Where the plist lives and which executable it launches. Injectable so
  /// tests never touch the real LaunchAgents folder.
  struct Location {
    var directory: URL
    var executablePath: String

    var plistURL: URL { directory.appendingPathComponent("\(LoginItem.label).plist") }

    static var live: Location {
      Location(
        directory: FileManager.default.homeDirectoryForCurrentUser
          .appendingPathComponent("Library/LaunchAgents"),
        executablePath: Bundle.main.executablePath ?? CommandLine.arguments[0])
    }
  }

  static var plistURL: URL { Location.live.plistURL }

  static var isEnabled: Bool { isEnabled(at: .live) }

  static var executablePath: String { Location.live.executablePath }

  static func isEnabled(at location: Location) -> Bool {
    FileManager.default.fileExists(atPath: location.plistURL.path)
  }

  /// Enabling always rewrites the plist so a stale executable path is
  /// corrected; disabling removes it. Neither touches the running launchd session.
  static func set(_ enabled: Bool, at location: Location = .live) {
    let fm = FileManager.default
    let url = location.plistURL
    if enabled {
      try? fm.createDirectory(at: location.directory, withIntermediateDirectories: true)
      let plist: [String: Any] = [
        "Label": label,
        "ProgramArguments": [location.executablePath],
        "RunAtLoad": true,
        "KeepAlive": false,
      ]
      guard
        let data = try? PropertyListSerialization.data(
          fromPropertyList: plist, format: .xml, options: 0)
      else { return }
      try? data.write(to: url)
    } else {
      try? fm.removeItem(at: url)
    }
  }
}

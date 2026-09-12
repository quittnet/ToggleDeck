import AppKit
import Foundation

/// ToggleDeck's own preferences, distinct from the system settings it controls.
@MainActor
final class AppSettings: ObservableObject {
  static let shared = AppSettings()

  private let store: UserDefaults
  /// Set while the observer is writing a read-back correction, so that write
  /// does not re-enter the observer and touch launchd a second time.
  private var applyingLoginItem = false

  /// IDs shown in the menu bar dropdown, in display order.
  @Published var pinned: [String] { didSet { store.set(pinned, forKey: "pinned") } }
  /// Restart Dock/Finder/Control Center automatically after a write that needs it.
  @Published var restartServices: Bool {
    didSet { store.set(restartServices, forKey: "restartServices") }
  }
  /// Show the one-line explanation under each switch in the dropdown.
  @Published var showDescriptions: Bool {
    didSet { store.set(showDescriptions, forKey: "showDescriptions") }
  }
  /// Group the dropdown by category instead of showing one flat list.
  @Published var groupDropdown: Bool {
    didSet { store.set(groupDropdown, forKey: "groupDropdown") }
  }
  /// Re-read every setting on a timer while a window is open.
  @Published var autoRefresh: Bool { didSet { store.set(autoRefresh, forKey: "autoRefresh") } }

  @Published var launchAtLogin: Bool {
    didSet {
      guard !applyingLoginItem else { return }
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

  init(store: UserDefaults = .standard) {
    self.store = store
    pinned = Self.migratedPins(store.array(forKey: "pinned") as? [String])
    restartServices = store.object(forKey: "restartServices") as? Bool ?? true
    showDescriptions = store.object(forKey: "showDescriptions") as? Bool ?? false
    groupDropdown = store.object(forKey: "groupDropdown") as? Bool ?? true
    autoRefresh = store.object(forKey: "autoRefresh") as? Bool ?? true
    launchAtLogin = LoginItem.isEnabled

    store.set(pinned, forKey: "pinned")
  }

  nonisolated static func migratedPins(_ saved: [String]?) -> [String] {
    guard let saved else { return Catalog.defaultPinned }
    if Array(saved.prefix(Catalog.previousDefaultPinned.count)) == Catalog.previousDefaultPinned {
      let extras = saved.dropFirst(Catalog.previousDefaultPinned.count)
      var seen = Set(Catalog.defaultPinned)
      return Catalog.defaultPinned
        + extras.filter { Catalog.byID[$0] != nil && seen.insert($0).inserted }
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
  }

  func resetPinned() { pinned = Catalog.defaultPinned }
}

// MARK: - Launch at login

/// Managed as a LaunchAgent rather than through SMAppService: the bundle is
/// ad-hoc signed, and SMAppService rejects registrations it cannot attribute to
/// a stable Developer ID.
enum LoginItem {
  static let label = "com.user.toggledeck"

  static var plistURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/LaunchAgents/\(label).plist")
  }

  static var isEnabled: Bool {
    FileManager.default.fileExists(atPath: plistURL.path)
  }

  static var executablePath: String {
    Bundle.main.executablePath ?? CommandLine.arguments[0]
  }

  static func set(_ enabled: Bool) {
    let fm = FileManager.default
    let url = plistURL
    if enabled {
      try? fm.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true)
      let plist: [String: Any] = [
        "Label": label,
        "ProgramArguments": [executablePath],
        "RunAtLoad": true,
        "KeepAlive": false,
      ]
      guard
        let data = try? PropertyListSerialization.data(
          fromPropertyList: plist, format: .xml, options: 0)
      else { return }
      // No `launchctl bootstrap`: the plist has RunAtLoad, so loading it now
      // would start a second copy next to this one. launchd picks the file
      // up at the next login, which is all "launch at login" needs.
      try? data.write(to: url)
    } else {
      // Remove the file only. `launchctl bootout` would SIGTERM this process
      // when launchd started it, killing the app before the plist was
      // deleted. With the file gone the job is not loaded at the next login.
      try? fm.removeItem(at: url)
    }
  }
}

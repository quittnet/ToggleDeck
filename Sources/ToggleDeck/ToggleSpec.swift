import Foundation

// MARK: - Categories

enum Category: String, CaseIterable, Identifiable, Codable, Sendable {
  case display = "Display"
  case connections = "Sound & Connections"
  case power = "Power"
  case desktop = "Dock & Desktop"
  case finder = "Finder"
  case input = "Typing & Trackpad"
  case screenshots = "Screenshots"

  var id: String { rawValue }
  var symbol: String {
    switch self {
    case .display: return "sun.max.fill"
    case .connections: return "wifi"
    case .power: return "bolt.fill"
    case .desktop: return "dock.rectangle"
    case .finder: return "folder.fill"
    case .input: return "keyboard.fill"
    case .screenshots: return "camera.viewfinder"
    }
  }
}

// MARK: - Requirements badges

struct Requirements: OptionSet, Sendable {
  let rawValue: Int
  static let admin = Requirements(rawValue: 1 << 0)  // prompts for your password
  static let fullDisk = Requirements(rawValue: 1 << 1)  // needs Full Disk Access
  static let automation = Requirements(rawValue: 1 << 2)  // needs Automation (AppleScript)
  static let restartApp = Requirements(rawValue: 1 << 3)  // affected app relaunches
  static let logout = Requirements(rawValue: 1 << 4)  // needs log out / restart
  static let appleSilicon = Requirements(rawValue: 1 << 5)
  static let laptopOnly = Requirements(rawValue: 1 << 6)

  var badges: [(String, String)] {  // (label, SF symbol)
    var out: [(String, String)] = []
    if contains(.admin) { out.append(("Password", "key.fill")) }
    if contains(.fullDisk) {
      out.append(("Full Disk Access", "externaldrive.fill.badge.person.crop"))
    }
    if contains(.automation) { out.append(("Automation", "gearshape.2.fill")) }
    if contains(.restartApp) { out.append(("Relaunches app", "arrow.clockwise")) }
    if contains(.logout) { out.append(("Log out required", "person.crop.circle.badge.xmark")) }
    if contains(.laptopOnly) { out.append(("Laptop only", "laptopcomputer")) }
    return out
  }
}

// MARK: - Services restarted after a write

enum Service: String, CaseIterable, Sendable {
  case dock = "Dock"
  case finder = "Finder"
  case systemUIServer = "SystemUIServer"
  case controlCenter = "ControlCenter"
  case windowManager = "WindowManager"
  case notificationCenter = "NotificationCenter"

  var killCommand: String { "/usr/bin/killall \(rawValue) >/dev/null 2>&1 || true" }
}

// MARK: - Preference domain scope

enum PrefScope: Sendable {
  /// ~/Library/Preferences/<domain>.plist
  case user
  /// ~/Library/Preferences/ByHost/<domain>.<uuid>.plist
  case byHost
  /// /Library/Preferences/<domain>.plist — writes need root.
  case system
}

// MARK: - How a boolean maps onto the stored preference value

enum PrefValue: Sendable {
  case boolean
  /// Stored value is the logical inverse of what the switch shows.
  case invertedBoolean
  case intMap(on: Int, off: Int)
  case stringMap(on: String, off: String)
  /// Any of these ints counts as ON; writes use `on` / `off`.
  case intSet(onValues: Set<Int>, on: Int, off: Int)

  func isOn(_ raw: Any?) -> Bool? {
    guard let raw else { return nil }
    switch self {
    case .boolean:
      return Self.asBool(raw)
    case .invertedBoolean:
      guard let b = Self.asBool(raw) else { return nil }
      return !b
    case .intMap(let on, _):
      guard let i = Self.asInt(raw) else { return nil }
      return i == on
    case .intSet(let onValues, _, _):
      guard let i = Self.asInt(raw) else { return nil }
      return onValues.contains(i)
    case .stringMap(let on, _):
      guard let s = raw as? String else { return nil }
      return s.caseInsensitiveCompare(on) == .orderedSame
    }
  }

  /// The `defaults write` type flag and literal for a given switch position.
  func writeLiteral(on: Bool) -> (flag: String, value: String) {
    switch self {
    case .boolean:
      return ("-bool", on ? "true" : "false")
    case .invertedBoolean:
      return ("-bool", on ? "false" : "true")
    case .intMap(let onV, let offV):
      return ("-int", String(on ? onV : offV))
    case .intSet(_, let onV, let offV):
      return ("-int", String(on ? onV : offV))
    case .stringMap(let onV, let offV):
      return ("-string", Shell.quote(on ? onV : offV))
    }
  }

  private static func asBool(_ raw: Any) -> Bool? {
    if let b = raw as? Bool { return b }
    if let n = raw as? NSNumber { return n.boolValue }
    if let s = raw as? String {
      switch s.lowercased() {
      case "1", "true", "yes", "on": return true
      case "0", "false", "no", "off": return false
      default: return nil
      }
    }
    return nil
  }

  private static func asInt(_ raw: Any) -> Int? {
    if let n = raw as? NSNumber { return n.intValue }
    if let s = raw as? String { return Int(s) }
    return nil
  }
}

// MARK: - Backing store for one toggle

struct DefaultsBacking: Sendable {
  var domain: String
  var key: String
  var value: PrefValue = .boolean
  var scope: PrefScope = .user
}

/// Custom bridges that cannot be expressed as a preference write.
enum Bridge: String, Sendable {
  case bluetooth
  case nightShift
  case trueTone
  case caffeinate
  case darkMode
}

enum Backend: Sendable {
  /// One preference key.
  case defaults(DefaultsBacking)
  /// Several keys written together; the first one is the source of truth for reads.
  case multiDefaults([DefaultsBacking])
  /// Arbitrary commands. `read` is parsed by `parse`; default parse is "1/true/on/yes/enabled".
  case shell(
    read: String, on: String, off: String, parse: (@Sendable (ShellResult) -> Bool?)? = nil)
  /// Native bridge implemented in SystemBridges.swift.
  case bridge(Bridge)
}

// MARK: - Toggle specification

struct ToggleSpec: Identifiable, Sendable {
  let id: String
  let title: String
  let detail: String
  let category: Category
  let backend: Backend
  /// What macOS does when the key has never been written.
  var systemDefault: Bool = false
  var requires: Requirements = []
  var restarts: [Service] = []
  /// When the read cannot be parsed, present the row as unsupported instead of
  /// falling back to `systemDefault`. Used for hardware-dependent settings such
  /// as High Power Mode, which simply do not appear in `pmset` on most Macs.
  var unsupportedIfUnreadable: Bool = false
  /// Extra search terms so "wifi", "dark", "ssh" etc. find the right row.
  var keywords: [String] = []

  var searchBlob: String {
    ([title, detail, category.rawValue] + keywords).joined(separator: " ").lowercased()
  }

  var needsAdmin: Bool { requires.contains(.admin) }
}

// MARK: - Live state of one toggle

struct ToggleState: Sendable {
  var isOn: Bool = false
  /// False when the backing key/binary/framework is missing on this Mac.
  var supported: Bool = true
  var busy: Bool = false
  /// Set when a write was attempted and the value did not stick.
  var error: String?
  /// True until the first successful read.
  var stale: Bool = true
}

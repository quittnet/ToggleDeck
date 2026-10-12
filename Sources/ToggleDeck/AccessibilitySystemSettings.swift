import AppKit
import CoreFoundation
import Darwin

struct PointerSettings: Equatable, Sendable {
  let scale: Double
  let shakeToFind: Bool

  static let standard = PointerSettings(scale: 1, shakeToFind: true)
  static let supportedScale = 1.0...4.0
  var isValid: Bool { scale.isFinite && Self.supportedScale.contains(scale) }
  var percentLabel: String { "\(Int((scale * 100).rounded()))%" }

  func matches(_ other: PointerSettings) -> Bool {
    abs(scale - other.scale) <= 0.0001 && shakeToFind == other.shakeToFind
  }
}

enum AccessibilitySettingKind: Sendable {
  case reduceMotion
  case reduceTransparency
  case shakePointer
}

/// Guarded native settings functions used by Apple's Accessibility pane.
/// Writes require both saved preference and actual system-state confirmation.
enum AccessibilitySystemSettings {
  private static let lock = NSRecursiveLock()
  private static let api = API()
  private static var domain: CFString { "com.apple.universalaccess" as CFString }
  struct PointerChanges: Equatable, Sendable {
    let scale: Bool
    let shake: Bool

    init(previous: PointerSettings, requested: PointerSettings) {
      scale = abs(previous.scale - requested.scale) > 0.0001
      shake = previous.shakeToFind != requested.shakeToFind
    }
  }

  // Protected preference writes can first require an asynchronous macOS
  // approval retry. Give that write time to finish before restoring the old
  // value, and keep flushing pending changes while checking the saved plist.
  private static let verificationAttempts = 200

  private static let saveError =
    "macOS could not save this accessibility setting. Enable Full Disk Access for the current ToggleDeck app, then quit and reopen it. You can also change it in Accessibility Display settings."

  static func read(_ kind: AccessibilitySettingKind) -> Bool? {
    lock.lock()
    defer { lock.unlock() }
    guard let api, api.setter(for: kind) != nil else { return nil }
    _ = synchronize(kind)
    return current(kind, using: api)
  }

  static func write(_ kind: AccessibilitySettingKind, enabled: Bool) -> String? {
    lock.lock()
    defer { lock.unlock() }
    guard let api, let setter = api.setter(for: kind),
      let previous = current(kind, using: api)
    else { return "This control is unavailable. Open Accessibility Display settings." }
    guard previous != enabled else { return nil }
    guard canReadSavedPreferences(for: kind) else { return saveError }
    setter(enabled ? 1 : 0)
    guard synchronize(kind) else {
      return failure(saveError, restored: restore(kind, previous: previous, using: api))
    }
    for attempt in 0..<verificationAttempts {
      if attempt > 0 { _ = synchronize(kind) }
      if current(kind, using: api) == enabled, savedBooleanMatches(kind, enabled: enabled) {
        return nil
      }
      if attempt + 1 < verificationAttempts { usleep(50_000) }
    }
    let message =
      "macOS did not save and apply this setting. Refresh or open Accessibility Display settings."
    return failure(message, restored: restore(kind, previous: previous, using: api))
  }

  static func readPointer() -> PointerSettings? {
    lock.lock()
    defer { lock.unlock() }
    guard let api, api.hasPointerControls else { return nil }
    _ = synchronizeScale()
    _ = synchronize(.shakePointer)
    return currentPointer(using: api)
  }

  static func writePointer(_ requested: PointerSettings) -> String? {
    lock.lock()
    defer { lock.unlock() }
    guard requested.isValid else { return "Choose a pointer size between 100% and 400%." }
    _ = synchronizeScale()
    guard let api, api.hasPointerControls, let previous = currentPointer(using: api) else {
      return
        "Pointer controls are unavailable. Open Pointer Settings to change the size or shake option."
    }
    guard !previous.matches(requested) else { return nil }
    let changes = PointerChanges(previous: previous, requested: requested)
    guard canReadSavedPreferences(for: changes) else { return saveError }
    apply(requested, previous: previous, using: api)
    guard synchronize(changes) else {
      return failure(saveError, restored: restore(previous, requested: requested, using: api))
    }
    for attempt in 0..<verificationAttempts {
      if attempt > 0 { _ = synchronize(changes) }
      if let actual = currentPointer(using: api), actual.matches(requested),
        savedPointerMatches(requested, changes: changes)
      {
        return nil
      }
      if attempt + 1 < verificationAttempts { usleep(50_000) }
    }
    let message =
      "macOS did not save and apply the pointer settings. Check Full Disk Access for ToggleDeck, then quit and reopen it. You can also use Pointer Settings."
    return failure(message, restored: restore(previous, requested: requested, using: api))
  }

  private static func current(_ kind: AccessibilitySettingKind, using api: API) -> Bool? {
    switch kind {
    case .reduceMotion: return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    case .reduceTransparency: return NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    case .shakePointer:
      guard api.connection() != 0, let getter = api.getShake else { return nil }
      return getter() != 0
    }
  }

  private static func currentPointer(using api: API) -> PointerSettings? {
    let connection = api.connection()
    guard connection != 0, let getter = api.getLiveScale, let getShake = api.getShake else {
      return nil
    }
    var scale: Float = 0
    guard getter(connection, &scale) == 0 else { return nil }
    let result = PointerSettings(scale: Double(scale), shakeToFind: getShake() != 0)
    return result.isValid ? result : nil
  }

  // CFPreferences can retain an optimistic in-process value after macOS rejects
  // a protected write. Read the saved plist independently before reporting success.
  private static func savedScaleMatches(_ requested: Double) -> Bool {
    guard let saved = try? PersistedAccessibilityPreferences.load(domain: .universalAccess) else {
      return false
    }
    return saved.scaleMatches(requested)
  }

  private static func savedBooleanMatches(_ kind: AccessibilitySettingKind, enabled: Bool) -> Bool {
    let domain: PersistedAccessibilityPreferences.Domain
    let key: String
    let expected: Bool
    switch kind {
    case .reduceMotion:
      domain = .universalAccess
      key = "reduceMotion"
      expected = enabled
    case .reduceTransparency:
      domain = .universalAccess
      key = "reduceTransparency"
      expected = enabled
    case .shakePointer:
      // SkyLight stores the inverse flag in the user's global preferences.
      domain = .global
      key = "CGDisableCursorLocationMagnification"
      expected = !enabled
    }
    guard let saved = try? PersistedAccessibilityPreferences.load(domain: domain) else {
      return false
    }
    return saved.booleanMatches(key: key, expected: expected, default: false)
  }

  private static func canReadSavedPreferences(for kind: AccessibilitySettingKind) -> Bool {
    let domain: PersistedAccessibilityPreferences.Domain =
      kind == .shakePointer ? .global : .universalAccess
    return (try? PersistedAccessibilityPreferences.load(domain: domain)) != nil
  }

  private static func canReadSavedPreferences(for changes: PointerChanges) -> Bool {
    (!changes.scale
      || (try? PersistedAccessibilityPreferences.load(domain: .universalAccess)) != nil)
      && (!changes.shake || (try? PersistedAccessibilityPreferences.load(domain: .global)) != nil)
  }

  private static func synchronize(_ kind: AccessibilitySettingKind) -> Bool {
    switch kind {
    case .reduceMotion, .reduceTransparency: return CFPreferencesAppSynchronize(domain)
    case .shakePointer:
      return CFPreferencesSynchronize(
        kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
  }

  private static func synchronizeScale() -> Bool {
    CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
  }

  private static func synchronize(_ changes: PointerChanges) -> Bool {
    var saved = true
    if changes.scale { saved = synchronizeScale() && saved }
    if changes.shake { saved = synchronize(.shakePointer) && saved }
    return saved
  }

  private static func savedPointerMatches(
    _ requested: PointerSettings, changes: PointerChanges
  ) -> Bool {
    (!changes.scale || savedScaleMatches(requested.scale))
      && (!changes.shake || savedBooleanMatches(.shakePointer, enabled: requested.shakeToFind))
  }

  private static func failure(_ message: String, restored: Bool) -> String {
    restored
      ? message
      : message
        + " The previous setting could not be confirmed as restored. Check Accessibility Display settings."
  }

  private static func restore(
    _ kind: AccessibilitySettingKind, previous: Bool, using api: API
  ) -> Bool {
    api.setter(for: kind)?(previous ? 1 : 0)
    var saved = synchronize(kind)
    for attempt in 0..<verificationAttempts {
      if attempt > 0 { saved = synchronize(kind) }
      if saved, current(kind, using: api) == previous,
        savedBooleanMatches(kind, enabled: previous)
      {
        return true
      }
      if attempt + 1 < verificationAttempts { usleep(50_000) }
    }
    return false
  }

  private static func apply(
    _ requested: PointerSettings, previous: PointerSettings, using api: API
  ) {
    // UACursorSetScale updates WindowServer before persisting its preference.
    // Confirm both so a protected preference write cannot look successful.
    if abs(previous.scale - requested.scale) > 0.0001 {
      api.setScale?(requested.scale)
      // UA can skip saving when its preference cache already contains the
      // requested value, including a previous write macOS rejected. Always save
      // the exact native scope, then confirm it independently on disk.
      CFPreferencesSetValue(
        "mouseDriverCursorSize" as CFString, NSNumber(value: requested.scale), domain,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
    if previous.shakeToFind != requested.shakeToFind {
      api.setShake?(requested.shakeToFind ? 1 : 0)
    }
  }

  private static func restore(
    _ previous: PointerSettings, requested: PointerSettings, using api: API
  ) -> Bool {
    let changes = PointerChanges(previous: requested, requested: previous)
    apply(previous, previous: requested, using: api)
    var saved = synchronize(changes)
    for attempt in 0..<verificationAttempts {
      if attempt > 0 { saved = synchronize(changes) }
      if saved, let actual = currentPointer(using: api), actual.matches(previous),
        savedPointerMatches(previous, changes: changes)
      {
        return true
      }
      if attempt + 1 < verificationAttempts { usleep(50_000) }
    }
    return false
  }

  private final class API: @unchecked Sendable {
    typealias GetBoolean = @convention(c) () -> UInt8
    typealias SetBoolean = @convention(c) (UInt8) -> Void
    typealias SetScale = @convention(c) (Double) -> Void
    typealias GetConnection = @convention(c) () -> UInt32
    typealias GetLiveScale = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32

    let setMotion: SetBoolean?
    let setTransparency: SetBoolean?
    let getShake: GetBoolean?
    let setShake: SetBoolean?
    let setScale: SetScale?
    let getConnection: GetConnection?
    let getLiveScale: GetLiveScale?

    var hasPointerControls: Bool {
      getShake != nil && setShake != nil && setScale != nil
        && getConnection != nil && getLiveScale != nil
    }

    init?() {
      let services = dlopen(
        "/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/HIServices",
        RTLD_LAZY | RTLD_LOCAL)
      let access = dlopen(
        "/System/Library/PrivateFrameworks/UniversalAccess.framework/UniversalAccess",
        RTLD_LAZY | RTLD_LOCAL)
      let graphics = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL)
      guard services != nil || access != nil else { return nil }
      setMotion = Self.function(services, "_AXInterfaceSetReduceMotionEnabled", SetBoolean.self)
      setTransparency = Self.function(
        services, "_AXInterfaceSetReduceTransparencyEnabled", SetBoolean.self)
      getShake = Self.function(access, "UAFindMyCursorIsEnabled", GetBoolean.self)
      setShake = Self.function(access, "UAFindMyCursorSetEnabled", SetBoolean.self)
      setScale = Self.function(access, "UACursorSetScale", SetScale.self)
      getConnection = Self.function(graphics, "SLSMainConnectionID", GetConnection.self)
      getLiveScale = Self.function(graphics, "SLSGetCursorScale", GetLiveScale.self)
      // Keep framework handles loaded for the lifetime of these function pointers.
    }

    func connection() -> UInt32 { getConnection?() ?? 0 }

    func setter(for kind: AccessibilitySettingKind) -> SetBoolean? {
      switch kind {
      case .reduceMotion: return setMotion
      case .reduceTransparency: return setTransparency
      case .shakePointer: return setShake
      }
    }

    private static func function<T>(
      _ handle: UnsafeMutableRawPointer?, _ name: String, _ type: T.Type
    ) -> T? {
      guard let handle, let pointer = dlsym(handle, name) else { return nil }
      return unsafeBitCast(pointer, to: type)
    }
  }
}

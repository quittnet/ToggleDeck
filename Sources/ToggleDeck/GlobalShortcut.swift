import Carbon
import Combine
import Foundation

enum GlobalShortcutKey: String, CaseIterable, Codable, Identifiable, Sendable {
  case a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z
  case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
  case space

  var id: String { rawValue }
  var title: String { self == .space ? "Space" : rawValue.uppercased() }

  /// Carbon key codes describe physical positions on an ANSI US keyboard.
  var keyCode: UInt32 {
    let value: Int
    switch self {
    case .a: value = kVK_ANSI_A
    case .b: value = kVK_ANSI_B
    case .c: value = kVK_ANSI_C
    case .d: value = kVK_ANSI_D
    case .e: value = kVK_ANSI_E
    case .f: value = kVK_ANSI_F
    case .g: value = kVK_ANSI_G
    case .h: value = kVK_ANSI_H
    case .i: value = kVK_ANSI_I
    case .j: value = kVK_ANSI_J
    case .k: value = kVK_ANSI_K
    case .l: value = kVK_ANSI_L
    case .m: value = kVK_ANSI_M
    case .n: value = kVK_ANSI_N
    case .o: value = kVK_ANSI_O
    case .p: value = kVK_ANSI_P
    case .q: value = kVK_ANSI_Q
    case .r: value = kVK_ANSI_R
    case .s: value = kVK_ANSI_S
    case .t: value = kVK_ANSI_T
    case .u: value = kVK_ANSI_U
    case .v: value = kVK_ANSI_V
    case .w: value = kVK_ANSI_W
    case .x: value = kVK_ANSI_X
    case .y: value = kVK_ANSI_Y
    case .z: value = kVK_ANSI_Z
    case .f1: value = kVK_F1
    case .f2: value = kVK_F2
    case .f3: value = kVK_F3
    case .f4: value = kVK_F4
    case .f5: value = kVK_F5
    case .f6: value = kVK_F6
    case .f7: value = kVK_F7
    case .f8: value = kVK_F8
    case .f9: value = kVK_F9
    case .f10: value = kVK_F10
    case .f11: value = kVK_F11
    case .f12: value = kVK_F12
    case .space: value = kVK_Space
    }
    return UInt32(value)
  }
}

struct GlobalShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
  let rawValue: UInt32

  static let command = GlobalShortcutModifiers(rawValue: UInt32(cmdKey))
  static let control = GlobalShortcutModifiers(rawValue: UInt32(controlKey))
  static let option = GlobalShortcutModifiers(rawValue: UInt32(optionKey))
  static let shift = GlobalShortcutModifiers(rawValue: UInt32(shiftKey))
  static let all: GlobalShortcutModifiers = [.command, .control, .option, .shift]

  var isValid: Bool {
    subtracting(.all).isEmpty && (contains(.command) || contains(.control))
  }

  var symbols: String {
    [(Self.control, "⌃"), (Self.option, "⌥"), (Self.shift, "⇧"), (Self.command, "⌘")]
      .filter { contains($0.0) }.map(\.1).joined()
  }
}

struct GlobalShortcut: Codable, Equatable, Sendable {
  var key: GlobalShortcutKey
  var modifiers: GlobalShortcutModifiers

  static let `default` = GlobalShortcut(key: .t, modifiers: [.control, .option, .command])
  var isValid: Bool { modifiers.isValid }
  var displayName: String { modifiers.symbols + key.title }
}

struct GlobalShortcutRegistration: Sendable {
  /// Cancellation is idempotent. A failure keeps the registration usable.
  let unregister: @MainActor @Sendable () -> String?
}

struct GlobalShortcutRegistrationError: Error, Equatable, Sendable {
  let message: String
}

struct GlobalShortcutBackend: Sendable {
  typealias Action = @MainActor @Sendable () -> Void
  let register:
    @MainActor @Sendable (GlobalShortcut, @escaping Action) -> Result<
      GlobalShortcutRegistration, GlobalShortcutRegistrationError
    >

  static let live = GlobalShortcutBackend { shortcut, action in
    CarbonGlobalShortcutRegistrar.shared.register(shortcut, action: action)
  }
  static let preview = GlobalShortcutBackend { _, _ in
    .success(GlobalShortcutRegistration(unregister: { nil }))
  }
}

/// Coordinates an app-owned shortcut without monitoring keyboard input.
@MainActor
final class GlobalShortcutController: ObservableObject {
  static let shared = GlobalShortcutController()
  static let storageKey = "globalShortcut.v1"

  @Published private(set) var enabled: Bool
  @Published private(set) var shortcut: GlobalShortcut
  @Published private(set) var activeShortcut: GlobalShortcut?
  @Published private(set) var error: String?

  private let store: UserDefaults?
  private let backend: GlobalShortcutBackend
  private var action: GlobalShortcutBackend.Action?
  private var running = false
  private var registration: GlobalShortcutRegistration?
  private var retired: [GlobalShortcutRegistration] = []
  private var nextGeneration: UInt64 = 0
  private var activeGeneration: UInt64?

  init(store: UserDefaults? = .standard, backend: GlobalShortcutBackend = .live) {
    self.store = store
    self.backend = backend
    let saved = store?.data(forKey: Self.storageKey)
      .flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) }
    if let saved, saved.shortcut.isValid {
      enabled = saved.enabled
      shortcut = saved.shortcut
    } else {
      enabled = true
      shortcut = .default
    }
  }

  static func preview() -> GlobalShortcutController {
    GlobalShortcutController(store: nil, backend: .preview)
  }

  func start(action: @escaping GlobalShortcutBackend.Action) {
    self.action = action
    running = true
    cleanRetiredRegistrations()
    guard enabled, registration == nil else { return }
    _ = activate(shortcut)
  }

  func shutdown() {
    running = false
    action = nil
    if let registration {
      if let failure = registration.unregister() {
        retired.append(registration)
        error = failure
      }
    }
    registration = nil
    activeShortcut = nil
    activeGeneration = nil
    cleanRetiredRegistrations()
  }

  @discardableResult
  func setEnabled(_ requested: Bool) -> Bool {
    if requested == enabled {
      if requested, running, registration == nil { return activate(shortcut) }
      return true
    }
    if requested {
      guard !running || activate(shortcut) else { return false }
    } else if let registration {
      if let failure = registration.unregister() {
        error = failure
        return false
      }
      self.registration = nil
      activeShortcut = nil
      activeGeneration = nil
    }
    enabled = requested
    error = nil
    persist()
    return true
  }

  /// Register the replacement before releasing the working shortcut. If either
  /// step fails, the previous configuration and saved preferences remain intact.
  @discardableResult
  func update(_ requested: GlobalShortcut) -> Bool {
    guard requested.isValid else {
      error = "Include Control or Command in the shortcut."
      return false
    }
    if running && enabled {
      if requested != activeShortcut {
        guard activate(requested) else { return false }
      }
    }
    shortcut = requested
    error = nil
    persist()
    return true
  }

  private func activate(_ requested: GlobalShortcut) -> Bool {
    nextGeneration &+= 1
    let generation = nextGeneration
    let result = backend.register(requested) { [weak self] in
      guard let self, self.running, self.enabled, self.activeShortcut == requested,
        self.activeGeneration == generation
      else { return }
      self.action?()
    }
    switch result {
    case .failure(let failure):
      error = failure.message
      return false
    case .success(let replacement):
      if let registration, let failure = registration.unregister() {
        if replacement.unregister() != nil { retired.append(replacement) }
        error = failure
        return false
      }
      registration = replacement
      activeShortcut = requested
      activeGeneration = generation
      error = nil
      return true
    }
  }

  private func cleanRetiredRegistrations() {
    retired = retired.filter { $0.unregister() != nil }
  }

  private func persist() {
    guard let store,
      let data = try? JSONEncoder().encode(Preferences(enabled: enabled, shortcut: shortcut))
    else { return }
    store.set(data, forKey: Self.storageKey)
  }

  deinit {
    let cleanup = retired + (registration.map { [$0] } ?? [])
    guard !cleanup.isEmpty else { return }
    Task { @MainActor in
      for item in cleanup { _ = item.unregister() }
    }
  }

  private struct Preferences: Codable {
    let enabled: Bool
    let shortcut: GlobalShortcut
  }
}

/// All Carbon operations and callback lookup run on the main actor. The C
/// callback passes only an integer ID to that actor, never a Swift object pointer.
@MainActor
private final class CarbonGlobalShortcutRegistrar {
  static let shared = CarbonGlobalShortcutRegistrar()
  nonisolated static let signature: OSType = 0x5447_444B  // TGDK

  private var handler: EventHandlerRef?
  private var nextID: UInt32 = 0
  private var references: [UInt32: EventHotKeyRef] = [:]
  private var actions: [UInt32: GlobalShortcutBackend.Action] = [:]

  func register(
    _ shortcut: GlobalShortcut, action: @escaping GlobalShortcutBackend.Action
  ) -> Result<GlobalShortcutRegistration, GlobalShortcutRegistrationError> {
    guard shortcut.isValid else {
      return .failure(
        GlobalShortcutRegistrationError(message: "Include Control or Command in the shortcut."))
    }
    if handler == nil {
      var spec = EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
      let status = InstallEventHandler(
        GetApplicationEventTarget(), globalShortcutEventHandler, 1, &spec, nil, &handler)
      guard status == noErr, handler != nil else {
        return .failure(
          GlobalShortcutRegistrationError(
            message: "macOS could not listen for the shortcut (error \(status)). Try again."))
      }
    }
    repeat { nextID &+= 1 } while nextID == 0 || references[nextID] != nil
    let identifier = nextID
    var reference: EventHotKeyRef?
    let status = RegisterEventHotKey(
      shortcut.key.keyCode, shortcut.modifiers.rawValue,
      EventHotKeyID(signature: Self.signature, id: identifier), GetApplicationEventTarget(),
      OptionBits(kEventHotKeyExclusive), &reference)
    guard status == noErr, let reference else {
      removeUnusedHandler()
      let message =
        status == eventHotKeyExistsErr
        ? "That shortcut is already in use. Choose another key or modifier combination."
        : "macOS could not register that shortcut (error \(status)). Choose another combination."
      return .failure(GlobalShortcutRegistrationError(message: message))
    }
    references[identifier] = reference
    actions[identifier] = action
    return .success(
      GlobalShortcutRegistration(unregister: { Self.shared.unregister(identifier) }))
  }

  func invoke(_ identifier: UInt32) { actions[identifier]?() }

  private func unregister(_ identifier: UInt32) -> String? {
    guard let reference = references[identifier] else { return nil }
    let status = UnregisterEventHotKey(reference)
    guard status == noErr else {
      return "macOS could not release the previous shortcut (error \(status)). Try again."
    }
    references.removeValue(forKey: identifier)
    actions.removeValue(forKey: identifier)
    removeUnusedHandler()
    return nil
  }

  private func removeUnusedHandler() {
    guard references.isEmpty, let handler else { return }
    if RemoveEventHandler(handler) == noErr { self.handler = nil }
  }
}

private func globalShortcutEventHandler(
  _: EventHandlerCallRef?, _ event: EventRef?, _: UnsafeMutableRawPointer?
) -> OSStatus {
  guard Thread.isMainThread, let event else { return OSStatus(eventNotHandledErr) }
  var identifier = EventHotKeyID()
  let status = GetEventParameter(
    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
    MemoryLayout<EventHotKeyID>.size, nil, &identifier)
  guard status == noErr, identifier.signature == CarbonGlobalShortcutRegistrar.signature else {
    return OSStatus(eventNotHandledErr)
  }
  let id = identifier.id
  Task { @MainActor in CarbonGlobalShortcutRegistrar.shared.invoke(id) }
  return noErr
}

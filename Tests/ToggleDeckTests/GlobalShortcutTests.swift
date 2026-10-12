import Carbon
import Foundation
import Testing

@testable import ToggleDeck

@Suite(.serialized)
struct GlobalShortcutTests {
  @Test
  func testDefaultShortcutAndSelectablePhysicalKeys() {
    #expect(GlobalShortcut.default.key == .t)
    #expect(GlobalShortcut.default.modifiers == [.control, .option, .command])
    #expect(GlobalShortcut.default.displayName == "⌃⌥⌘T")
    #expect(GlobalShortcut.default.isValid)
    #expect(GlobalShortcutKey.t.keyCode == UInt32(kVK_ANSI_T))
    #expect(GlobalShortcutKey.f12.keyCode == UInt32(kVK_F12))
    #expect(GlobalShortcutKey.space.keyCode == UInt32(kVK_Space))
    #expect(GlobalShortcutKey.space.title == "Space")
    #expect(GlobalShortcutKey.allCases.count == 39)
    #expect(Set(GlobalShortcutKey.allCases.map(\.keyCode)).count == 39)
  }

  @Test
  func testValidationRequiresControlOrCommandAndRejectsUnknownModifiers() {
    for modifiers: GlobalShortcutModifiers in [[], .option, .shift, [.option, .shift]] {
      #expect(!GlobalShortcut(key: .space, modifiers: modifiers).isValid)
    }
    for modifiers: GlobalShortcutModifiers in [.command, .control, [.control, .shift], .all] {
      #expect(GlobalShortcut(key: .f1, modifiers: modifiers).isValid)
    }
    let unknown = GlobalShortcutModifiers(
      rawValue: GlobalShortcutModifiers.command.rawValue | (1 << 31))
    #expect(!GlobalShortcut(key: .a, modifiers: unknown).isValid)
    #expect(GlobalShortcut(key: .f5, modifiers: [.control, .shift]).displayName == "⌃⇧F5")
  }

  @MainActor
  @Test
  func testConfigurationAndDisabledStatePersistWithoutRegistering() throws {
    try withIsolatedStore { store in
      let fake = FakeGlobalShortcutRegistrar()
      let controller = GlobalShortcutController(store: store, backend: fake.backend)
      let custom = GlobalShortcut(key: .space, modifiers: [.control, .shift])
      #expect(controller.update(custom))
      #expect(controller.setEnabled(false))
      #expect(fake.attempted.isEmpty)
      let restored = GlobalShortcutController(store: store, backend: fake.backend)
      #expect(restored.shortcut == custom)
      #expect(!restored.enabled)
      #expect(restored.activeShortcut == nil)
      restored.start(action: {})
      #expect(fake.attempted.isEmpty)
    }
  }

  @MainActor
  @Test
  func testMalformedSavedShortcutFallsBackWithoutReservingAKey() throws {
    try withIsolatedStore { store in
      let fake = FakeGlobalShortcutRegistrar()
      store.set(Data("invalid json".utf8), forKey: GlobalShortcutController.storageKey)
      let malformed = GlobalShortcutController(store: store, backend: fake.backend)
      #expect(malformed.shortcut == .default)
      #expect(malformed.activeShortcut == nil)
      let invalid: [String: Any] = [
        "enabled": true, "shortcut": ["key": "t", "modifiers": ["rawValue": 0]],
      ]
      store.set(
        try JSONSerialization.data(withJSONObject: invalid),
        forKey: GlobalShortcutController.storageKey)
      let noModifiers = GlobalShortcutController(store: store, backend: fake.backend)
      #expect(noModifiers.shortcut == .default)
      #expect(noModifiers.activeShortcut == nil)
      #expect(fake.attempted.isEmpty)
    }
  }

  @MainActor
  @Test
  func testMemoryPreviewsCannotChangeAnotherPreview() {
    let first = GlobalShortcutController.preview()
    let second = GlobalShortcutController.preview()
    first.start(action: {})
    #expect(first.activeShortcut == .default)
    #expect(first.update(GlobalShortcut(key: .p, modifiers: .command)))
    #expect(first.setEnabled(false))
    #expect(second.shortcut == .default)
    #expect(second.enabled)
    #expect(second.activeShortcut == nil)
    #expect(GlobalShortcutController.preview().shortcut == .default)
    first.shutdown()
  }

  @MainActor
  @Test
  func testRepeatedStartKeepsOneRegistrationAndUsesLatestAction() {
    let fake = FakeGlobalShortcutRegistrar()
    let controller = GlobalShortcutController(store: nil, backend: fake.backend)
    let counter = ShortcutCounter()
    controller.start { counter.value += 1 }
    controller.start { counter.value += 10 }
    #expect(fake.attempted == [.default])
    #expect(fake.registered.count == 1)
    fake.fireHistorical(1)
    #expect(counter.value == 10)
    controller.shutdown()
    #expect(fake.registered.isEmpty)
  }

  @MainActor
  @Test
  func testFailedReplacementPreservesWorkingShortcutAndSavedConfiguration() throws {
    try withIsolatedStore { store in
      let fake = FakeGlobalShortcutRegistrar()
      let controller = GlobalShortcutController(store: store, backend: fake.backend)
      let original = GlobalShortcut(key: .o, modifiers: [.control, .option])
      #expect(controller.update(original))
      let counter = ShortcutCounter()
      controller.start { counter.value += 1 }
      fake.registrationFailure = "That shortcut is already in use."
      #expect(!controller.update(GlobalShortcut(key: .q, modifiers: .command)))
      #expect(controller.shortcut == original)
      #expect(controller.activeShortcut == original)
      #expect(controller.error == "That shortcut is already in use.")
      #expect(fake.registered.count == 1)
      #expect(fake.unregistered.isEmpty)
      #expect(GlobalShortcutController(store: store, backend: fake.backend).shortcut == original)
      fake.fireHistorical(1)
      #expect(counter.value == 1)
      controller.shutdown()
    }
  }

  @MainActor
  @Test
  func testSuccessfulReplacementRegistersBeforeReleasingOldKey() throws {
    try withIsolatedStore { store in
      let fake = FakeGlobalShortcutRegistrar()
      let controller = GlobalShortcutController(store: store, backend: fake.backend)
      let counter = ShortcutCounter()
      controller.start { counter.value += 1 }
      let replacement = GlobalShortcut(key: .f8, modifiers: [.control, .option])
      #expect(controller.update(replacement))
      #expect(fake.events == ["register:1", "register:2", "unregister:1"])
      #expect(fake.registered.count == 1)
      #expect(controller.activeShortcut == replacement)
      #expect(controller.shortcut == replacement)
      #expect(controller.error == nil)
      #expect(GlobalShortcutController(store: store, backend: fake.backend).shortcut == replacement)
      fake.fireHistorical(1)
      #expect(counter.value == 0)
      fake.fireHistorical(2)
      #expect(counter.value == 1)
      controller.shutdown()
    }
  }

  @MainActor
  @Test
  func testFailureReleasingOldKeyRollsBackReplacement() {
    let fake = FakeGlobalShortcutRegistrar()
    let controller = GlobalShortcutController(store: nil, backend: fake.backend)
    let counter = ShortcutCounter()
    controller.start { counter.value += 1 }
    fake.releaseFailures = [1]
    #expect(!controller.update(GlobalShortcut(key: .f9, modifiers: .command)))
    #expect(controller.shortcut == .default)
    #expect(controller.activeShortcut == .default)
    #expect(controller.error != nil)
    #expect(fake.registered.keys.sorted() == [1])
    #expect(fake.unregistered == [2])
    fake.fireHistorical(2)
    #expect(counter.value == 0)
    fake.fireHistorical(1)
    #expect(counter.value == 1)
    fake.releaseFailures = []
    controller.shutdown()
  }

  @MainActor
  @Test
  func testDisableReleasesShortcutAndEnableCreatesNewRegistration() throws {
    try withIsolatedStore { store in
      let fake = FakeGlobalShortcutRegistrar()
      let controller = GlobalShortcutController(store: store, backend: fake.backend)
      let counter = ShortcutCounter()
      controller.start { counter.value += 1 }
      #expect(controller.setEnabled(false))
      #expect(!controller.enabled)
      #expect(controller.activeShortcut == nil)
      #expect(fake.registered.isEmpty)
      #expect(!GlobalShortcutController(store: store, backend: fake.backend).enabled)
      fake.fireHistorical(1)
      #expect(counter.value == 0)
      #expect(controller.setEnabled(true))
      #expect(controller.enabled)
      #expect(controller.activeShortcut == .default)
      fake.fireHistorical(1)
      #expect(counter.value == 0)
      fake.fireHistorical(2)
      #expect(counter.value == 1)
      controller.shutdown()
    }
  }

  @MainActor
  @Test
  func testFailedEnablePreservesDisabledPreferenceAndRetryCanRecover() throws {
    try withIsolatedStore { store in
      let fake = FakeGlobalShortcutRegistrar()
      let controller = GlobalShortcutController(store: store, backend: fake.backend)
      #expect(controller.setEnabled(false))
      controller.start(action: {})
      fake.registrationFailure = "Reserved by another app."
      #expect(!controller.setEnabled(true))
      #expect(!controller.enabled)
      #expect(controller.activeShortcut == nil)
      #expect(controller.error == "Reserved by another app.")
      #expect(!GlobalShortcutController(store: store, backend: fake.backend).enabled)
      fake.registrationFailure = nil
      #expect(controller.setEnabled(true))
      #expect(controller.enabled)
      #expect(controller.activeShortcut == .default)
      #expect(controller.error == nil)
      controller.shutdown()
    }
  }

  @MainActor
  @Test
  func testFailedDisableKeepsWorkingShortcutAndEnabledPreference() {
    let fake = FakeGlobalShortcutRegistrar()
    let controller = GlobalShortcutController(store: nil, backend: fake.backend)
    controller.start(action: {})
    fake.releaseFailures = [1]
    #expect(!controller.setEnabled(false))
    #expect(controller.enabled)
    #expect(controller.activeShortcut == .default)
    #expect(fake.registered.count == 1)
    #expect(controller.error != nil)
    fake.releaseFailures = []
    controller.shutdown()
  }

  @MainActor
  @Test
  func testInvalidUpdateNeverTouchesWorkingRegistration() {
    let fake = FakeGlobalShortcutRegistrar()
    let controller = GlobalShortcutController(store: nil, backend: fake.backend)
    controller.start(action: {})
    #expect(!controller.update(GlobalShortcut(key: .space, modifiers: [.option, .shift])))
    #expect(controller.shortcut == .default)
    #expect(controller.activeShortcut == .default)
    #expect(controller.error == "Include Control or Command in the shortcut.")
    #expect(fake.attempted == [.default])
    #expect(fake.unregistered.isEmpty)
    controller.shutdown()
  }

  @MainActor
  @Test
  func testShutdownAndRestartIgnoreRetiredCallbacksForSameCombination() {
    let fake = FakeGlobalShortcutRegistrar()
    let controller = GlobalShortcutController(store: nil, backend: fake.backend)
    let counter = ShortcutCounter()
    controller.start { counter.value += 1 }
    controller.shutdown()
    #expect(controller.enabled)
    #expect(controller.activeShortcut == nil)
    #expect(fake.registered.isEmpty)
    fake.fireHistorical(1)
    #expect(counter.value == 0)
    controller.start { counter.value += 10 }
    fake.fireHistorical(1)
    #expect(counter.value == 0)
    fake.fireHistorical(2)
    #expect(counter.value == 10)
    controller.shutdown()
  }

  @MainActor
  @Test
  func testRegistrationCallbacksDoNotRetainController() async throws {
    let fake = FakeGlobalShortcutRegistrar()
    var controller: GlobalShortcutController? = GlobalShortcutController(
      store: nil, backend: fake.backend)
    weak let weakController = controller
    controller?.start(action: {})
    #expect(fake.registered.count == 1)
    controller = nil
    #expect(weakController == nil)
    for _ in 0..<20 where !fake.registered.isEmpty { await Task.yield() }
    #expect(fake.registered.isEmpty)
    fake.fireHistorical(1)
  }

  @MainActor
  private func withIsolatedStore(_ body: (UserDefaults) throws -> Void) throws {
    let suite = "com.user.toggledeck.shortcut.tests.\(UUID().uuidString)"
    let store = try #require(UserDefaults(suiteName: suite))
    defer { store.removePersistentDomain(forName: suite) }
    try body(store)
  }
}

@MainActor
private final class ShortcutCounter {
  var value = 0
}

@MainActor
private final class FakeGlobalShortcutRegistrar {
  var registrationFailure: String?
  var releaseFailures: Set<Int> = []
  private var nextID = 0
  private var historicalActions: [Int: GlobalShortcutBackend.Action] = [:]
  private(set) var registered: [Int: GlobalShortcut] = [:]
  private(set) var attempted: [GlobalShortcut] = []
  private(set) var unregistered: [Int] = []
  private(set) var events: [String] = []

  var backend: GlobalShortcutBackend {
    GlobalShortcutBackend { [self] shortcut, action in
      attempted.append(shortcut)
      if let registrationFailure {
        return .failure(GlobalShortcutRegistrationError(message: registrationFailure))
      }
      nextID += 1
      let id = nextID
      registered[id] = shortcut
      historicalActions[id] = action
      events.append("register:\(id)")
      return .success(
        GlobalShortcutRegistration(unregister: { [weak self] in
          guard let self, self.registered[id] != nil else { return nil }
          if self.releaseFailures.contains(id) { return "Could not release the working shortcut." }
          self.registered.removeValue(forKey: id)
          self.unregistered.append(id)
          self.events.append("unregister:\(id)")
          return nil
        }))
    }
  }

  func fireHistorical(_ id: Int) { historicalActions[id]?() }
}

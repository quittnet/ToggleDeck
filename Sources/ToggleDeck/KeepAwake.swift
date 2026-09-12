import Foundation
import IOKit.pwr_mgt

protocol PowerAssertionDriver: Sendable {
  func create(_ type: String) -> IOPMAssertionID?
  func release(_ id: IOPMAssertionID) -> Bool
}

struct NativePowerAssertionDriver: PowerAssertionDriver {
  func create(_ type: String) -> IOPMAssertionID? {
    var id: IOPMAssertionID = 0
    let result = IOPMAssertionCreateWithName(
      type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
      "ToggleDeck Keep Awake" as CFString, &id)
    return result == kIOReturnSuccess ? id : nil
  }

  func release(_ id: IOPMAssertionID) -> Bool {
    IOPMAssertionRelease(id) == kIOReturnSuccess
  }
}

/// Assertions belong to this process. macOS releases them even after a crash
/// or SIGTERM, so there is no independent caffeinate child to leave running.
final class KeepAwakeController: @unchecked Sendable {
  private let lock = NSLock()
  private let driver: any PowerAssertionDriver
  private var assertions: [IOPMAssertionID] = []

  init(driver: any PowerAssertionDriver = NativePowerAssertionDriver()) {
    self.driver = driver
  }

  var isOn: Bool {
    lock.lock()
    defer { lock.unlock() }
    return !assertions.isEmpty
  }

  func set(_ on: Bool) -> String? {
    lock.lock()
    defer { lock.unlock() }

    if !on {
      assertions = assertions.filter { !driver.release($0) }
      return assertions.isEmpty ? nil : "Could not release Keep Awake. Quit ToggleDeck to stop it."
    }
    if !assertions.isEmpty {
      return assertions.count == 2
        ? nil : "Keep Awake is partially active. Turn it off before trying again."
    }
    for type in [
      kIOPMAssertionTypePreventUserIdleDisplaySleep,
      kIOPMAssertionTypePreventUserIdleSystemSleep,
    ] {
      guard let id = driver.create(type) else {
        assertions = assertions.filter { !driver.release($0) }
        return "macOS could not enable Keep Awake."
      }
      assertions.append(id)
    }
    return nil
  }

  deinit {
    for id in assertions { _ = driver.release(id) }
  }
}

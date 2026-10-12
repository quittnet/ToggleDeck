import Foundation
import Testing

@testable import ToggleDeck

struct SquareWindowCornersTests {
  @Test
  func missingKeyDiagnosticsDoNotHideWriteFailures() {
    for message in [
      "The domain/default pair of (NSGlobalDomain, NSConvolutionOverride1) does not exist",
      "Error: Could not find key 'NSConvolutionOverride1' in domain 'kCFPreferencesAnyApplication'.",
    ] {
      #expect(Prefs.isMissingKeyError(ShellResult(status: 1, out: "", err: message)))
      #expect(!Prefs.isMissingKeyError(ShellResult(status: -2, out: "", err: message)))
    }
    #expect(
      !Prefs.isMissingKeyError(ShellResult(status: 1, out: "", err: "Could not write domain")))
    #expect(
      !Prefs.isMissingKeyError(ShellResult(status: 1, out: "", err: "Operation not permitted")))
  }

  @Test
  func overrideReadsExactRadiusAndAbsentDefault() {
    let value = PrefValue.floatOverride(on: 1)
    for raw: Any in [NSNumber(value: 1.0), NSNumber(value: 1), "1", "1.0", " 1.000\n"] {
      #expect(value.isOn(raw) == true)
      #expect(value.isOn(raw, verifyingWrite: true) == true)
    }
    #expect(value.isOn(nil) == false)
    #expect(value.isOn(nil, verifyingWrite: true) == false)
    for raw: Any in [NSNumber(value: 0.0), NSNumber(value: 1.5), "2"] {
      #expect(value.isOn(raw) == false)
      // Another radius must not pass verification of OFF: the key must be absent.
      #expect(value.isOn(raw, verifyingWrite: true) == nil)
    }
    for raw: Any in [NSNumber(value: true), "true", "invalid", "nan", "inf"] {
      #expect(value.isOn(raw) == nil)
    }
    #expect(PrefValue.boolean.isOn(nil, verifyingWrite: true) == nil)
  }

  @Test
  func catalogWritesFloatAndDeletesForOff() throws {
    let spec = try #require(Catalog.byID["squareWindowCorners"])
    guard case .defaults(let backing) = spec.backend else {
      Issue.record("Square corners must use the global preference backend")
      return
    }
    #expect(backing.domain == "NSGlobalDomain")
    #expect(backing.key == "NSConvolutionOverride1")
    #expect(backing.scope == .user)
    #expect(
      Prefs.writeCommand(backing, on: true)
        == "/usr/bin/defaults write 'NSGlobalDomain' 'NSConvolutionOverride1' -float 1.0")
    #expect(
      Prefs.writeCommand(backing, on: false)
        == "/usr/bin/defaults delete 'NSGlobalDomain' 'NSConvolutionOverride1'")
    #expect(spec.category == .display)
    #expect(!spec.systemDefault)
    #expect(spec.restarts.isEmpty)
    #expect(!spec.needsAdmin)
    #expect(spec.requires.contains(.mayNeedAppRestart))
    #expect(spec.menuSubtitle(showDescriptions: false) == "May need app restart")
    #expect(spec.menuHelp.contains("Apps may need to restart."))
    #expect(SettingSearch.results(in: Catalog.all, query: "rounded corners").map(\.id) == [spec.id])
  }

  @Test
  func readsStoredOverrideAndVerifiesRemoval() throws {
    let domain = "com.user.toggledeck.tests.squareCorners.\(UUID().uuidString)"
    let store = try #require(UserDefaults(suiteName: domain))
    defer { store.removePersistentDomain(forName: domain) }
    // Use a unique key so CFPreferences cannot inherit the real global override.
    let key = "SquareCornersTestOverride"
    let spec = ToggleSpec(
      id: "squareWindowCorners", title: "Square Window Corners", detail: "", category: .display,
      backend: .defaults(DefaultsBacking(domain: domain, key: key, value: .floatOverride(on: 1))))

    #expect(!ToggleEngine.read(spec).isOn)
    store.set(1.0, forKey: key)
    store.synchronize()
    let enabled = ToggleEngine.read(spec)
    #expect(enabled.isOn && enabled.supported && !enabled.stale)
    #expect(ToggleEngine.verificationError(spec, requested: true, actual: enabled) == nil)

    store.set(1.5, forKey: key)
    store.synchronize()
    let leftover = ToggleEngine.read(spec, verifyingWrite: true)
    #expect(ToggleEngine.verificationError(spec, requested: false, actual: leftover) != nil)

    store.removeObject(forKey: key)
    store.synchronize()
    let removed = ToggleEngine.read(spec, verifyingWrite: true)
    #expect(removed.supported && !removed.isOn && !removed.stale)
    #expect(ToggleEngine.verificationError(spec, requested: false, actual: removed) == nil)
    #expect(ToggleEngine.verificationError(spec, requested: true, actual: removed) != nil)
  }

  @Test
  func addsToPreviousDefaultMenusAndPreservesCustomMenus() {
    #expect(Catalog.version26DefaultPinned.count == 22)
    #expect(Catalog.versionTwoDefaultPinned.count == 20)
    #expect(AppSettings.migratedPins(Catalog.version26DefaultPinned) == Catalog.defaultPinned)
    #expect(AppSettings.migratedPins(Catalog.versionTwoDefaultPinned) == Catalog.defaultPinned)
    let custom = Array(Catalog.version26DefaultPinned.reversed())
    #expect(AppSettings.migratedPins(custom) == custom)
    #expect(AppSettings.migratedPins(["darkMode", "wifi"]) == ["darkMode", "wifi"])
    #expect(AppSettings.migratedPins([]) == [])
  }
}

import Foundation
import Testing

@testable import ToggleDeck

@MainActor
@Suite
struct PinnedMigrationTests {
  private func withStore(_ body: (UserDefaults) -> Void) {
    let suite = "com.user.toggledeck.tests.\(UUID().uuidString)"
    let store = UserDefaults(suiteName: suite)!
    defer { store.removePersistentDomain(forName: suite) }
    body(store)
  }

  private func settings(_ store: UserDefaults) -> AppSettings {
    AppSettings(store: store, manageLoginItem: false)
  }

  private func version(_ store: UserDefaults) -> Int? {
    store.object(forKey: AppSettings.pinnedSchemaVersionKey) as? Int
  }

  @Test
  func testLegacyDefaultIsUpgradedOnceThenRemovalSticks() {
    withStore { store in
      store.set(Catalog.version26DefaultPinned, forKey: "pinned")
      let first = settings(store)
      #expect(first.pinned == Catalog.defaultPinned)
      #expect(version(store) == AppSettings.currentPinnedSchemaVersion)

      first.togglePin("squareWindowCorners")
      #expect(!first.pinned.contains("squareWindowCorners"))
      let second = settings(store)
      #expect(!second.pinned.contains("squareWindowCorners"))
      #expect(second.pinned == first.pinned)
    }
  }

  @Test
  func testOldDefaultListsAreKeptAtCurrentVersion() {
    let custom = Catalog.previousDefaultPinned + ["trueTone"]
    for saved in [Catalog.versionTwoDefaultPinned, Catalog.version26DefaultPinned, custom] {
      withStore { store in
        store.set(saved, forKey: "pinned")
        store.set(
          AppSettings.currentPinnedSchemaVersion, forKey: AppSettings.pinnedSchemaVersionKey)
        #expect(settings(store).pinned == saved)
        #expect(settings(store).pinned == saved)
      }
    }
  }

  @Test
  func testCleanupIsUnconditionalAtCurrentVersion() {
    #expect(
      AppSettings.migratedPins(
        ["wifi", "capsLockEscape", "darkMode", "wifi"],
        schemaVersion: AppSettings.currentPinnedSchemaVersion) == ["wifi", "darkMode"])
    #expect(
      AppSettings.migratedPins([], schemaVersion: AppSettings.currentPinnedSchemaVersion) == [])
    #expect(
      AppSettings.migratedPins(
        ["capsLockEscape"], schemaVersion: AppSettings.currentPinnedSchemaVersion)
        == Catalog.defaultPinned)
  }

  @Test
  func testEmptyListSurvivesRelaunch() {
    withStore { store in
      store.set([String](), forKey: "pinned")
      store.set(AppSettings.currentPinnedSchemaVersion, forKey: AppSettings.pinnedSchemaVersionKey)
      #expect(settings(store).pinned.isEmpty)
      #expect(settings(store).pinned.isEmpty)
    }
  }

  @Test
  func testFreshStoreGetsDefaultAndCurrentVersion() {
    withStore { store in
      #expect(settings(store).pinned == Catalog.defaultPinned)
      #expect(version(store) == AppSettings.currentPinnedSchemaVersion)
    }
  }
}

@Suite
struct LoginItemTests {
  private func withLocation(
    path: String = "/Applications/ToggleDeck",
    _ body: (LoginItem.Location) throws -> Void
  ) rethrows {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("toggledeck-login-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try body(
      LoginItem.Location(
        directory: root.appendingPathComponent("LaunchAgents"), executablePath: path))
  }

  private func readPlist(_ location: LoginItem.Location) throws -> [String: Any] {
    let data = try Data(contentsOf: location.plistURL)
    return try #require(
      try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
  }

  @Test
  func testEnablingCreatesValidPlistAndMissingDirectory() throws {
    try withLocation { location in
      #expect(!FileManager.default.fileExists(atPath: location.directory.path))
      LoginItem.set(true, at: location)
      #expect(LoginItem.isEnabled(at: location))
      let plist = try readPlist(location)
      #expect(plist["Label"] as? String == "com.user.toggledeck")
      #expect(plist["ProgramArguments"] as? [String] == [location.executablePath])
      #expect(plist["RunAtLoad"] as? Bool == true)
      #expect(plist["KeepAlive"] as? Bool == false)
    }
  }

  @Test
  func testEnablingAgainRewritesStalePath() throws {
    try withLocation { location in
      var stale = location
      stale.executablePath = "/old/build/ToggleDeck"
      LoginItem.set(true, at: stale)
      LoginItem.set(true, at: location)
      let plist = try readPlist(location)
      #expect(plist["ProgramArguments"] as? [String] == [location.executablePath])
    }
  }

  @Test
  func testDisablingRemovesFileAndIsHarmlessWhenAbsent() {
    withLocation { location in
      LoginItem.set(false, at: location)
      #expect(!LoginItem.isEnabled(at: location))
      LoginItem.set(true, at: location)
      LoginItem.set(false, at: location)
      #expect(!LoginItem.isEnabled(at: location))
      #expect(!FileManager.default.fileExists(atPath: location.plistURL.path))
    }
  }
}

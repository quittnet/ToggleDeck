import Foundation
import IOKit.pwr_mgt
import Testing

@testable import ToggleDeck

@Suite(.serialized)
struct ToggleDeckTests {
  @Test
  func testAllControlsFitOnLaptopAndDesktop() async {
    await MainActor.run {
      let items = Category.allCases.flatMap { category -> [DropdownLayout.Item] in
        [.header(category)] + Catalog.all.filter { $0.category == category }.map { .row($0) }
      }
      for (size, columns) in [
        (CGSize(width: 1280, height: 752), 3), (CGSize(width: 1920, height: 1156), 2),
      ] {
        let result = DropdownLayout.pack(items, showDescriptions: false, screenSize: size)
        #expect(result.columns.count == columns)
        #expect(!(result.overflowed))
        let ids = result.columns.flatMap { $0 }.compactMap { item -> String? in
          if case .row(let spec) = item { return spec.id }
          return nil
        }
        #expect(ids.count == 23)
        #expect(Set(ids) == Set(Catalog.defaultPinned))
        for column in result.columns {
          var category: ToggleDeck.Category?
          for item in column {
            switch item {
            case .header(let value): category = value
            case .row(let spec): #expect(spec.category == category)
            case .cursorColor: #expect(category == .display)
            case .audioOutput: #expect(category == .connections)
            }
          }
        }
      }
    }
  }

  @Test
  func testDescriptionsScrollWithoutSplittingCategories() async {
    await MainActor.run {
      let items = Category.allCases.flatMap { category -> [DropdownLayout.Item] in
        [.header(category)] + Catalog.all.filter { $0.category == category }.map { .row($0) }
      }
      let result = DropdownLayout.pack(
        items, showDescriptions: true,
        screenSize: CGSize(width: 1280, height: 752))
      #expect(result.overflowed)
      #expect(result.width <= 1280)
      #expect(result.columns.flatMap { $0 }.count == 30)
    }
  }

  @Test
  func testFlatColumnsPreserveCustomOrder() async {
    await MainActor.run {
      let specs = Array(Catalog.all.reversed())
      let result = DropdownLayout.pack(
        specs.map { .row($0) }, showDescriptions: false,
        screenSize: CGSize(width: 1280, height: 752))
      let ids = result.columns.flatMap { $0 }.map(\.id)
      #expect(ids == specs.map { "r:\($0.id)" })
      #expect(!(result.overflowed))
    }
  }

  @Test
  func testSearchAndEmptyLayoutsStayCompact() async {
    await MainActor.run {
      let result = DropdownLayout.pack(
        [.row(Catalog.all[0])], showDescriptions: false,
        screenSize: CGSize(width: 1280, height: 752))
      #expect(result.columns.count == 1)
      #expect(result.width == 360)
      let empty = DropdownLayout.pack([], showDescriptions: false)
      #expect(!(empty.overflowed))
      #expect(empty.width == 360)
    }
  }

  @MainActor
  @Test
  func testPreviewChangesStayInMemory() async {
    let first = ToggleEngine.preview()
    let second = ToggleEngine.preview()
    let initial = first.state("wifi").isOn
    await first.set("wifi", on: !initial)
    await first.refreshAll()
    #expect(first.state("wifi").isOn == !initial)
    #expect(second.state("wifi").isOn == initial)
    #expect(first.banner == nil)
  }

  @Test
  func testCuratedCatalogHasOnlyEverydayControls() {
    #expect(Catalog.all.count == 23)
    #expect(Catalog.byID.count == 23)
    #expect(Catalog.defaultPinned.count == 23)
    #expect(Set(Catalog.defaultPinned) == Set(Catalog.all.map(\.id)))
    for id in Catalog.defaultPinned { #expect(Catalog.byID[id] != nil) }
    for id in ["capsLockEscape", "autoSpellCheck", "firewall", "remoteLogin", "quarantineWarning"] {
      #expect(Catalog.byID[id] == nil)
    }
    for category in Category.allCases {
      #expect(Catalog.all.contains { $0.category == category })
    }
  }

  @Test
  func testNoDuplicateSinglePreferenceControls() {
    var keys = Set<String>()
    for spec in Catalog.all {
      if case .defaults(let backing) = spec.backend {
        #expect(
          keys.insert("\(backing.domain):\(backing.key):\(backing.scope)").inserted,
          Comment(rawValue: spec.id))
      }
    }
  }

  @Test
  func testDesktopItemsToggleKeepsFinderDesktopEnabled() throws {
    let spec = try #require(Catalog.byID["showDesktopIcons"])
    guard case .shell(_, let on, let off, let parse) = spec.backend else {
      Issue.record("Desktop items must use the WindowManager setting")
      return
    }
    for command in [on, off] {
      #expect(command.contains("com.apple.finder CreateDesktop -bool true"))
    }
    #expect(on.contains("StandardHideDesktopIcons -bool false"))
    #expect(off.contains("StandardHideDesktopIcons -bool true"))
    #expect(parse?(ShellResult(status: 0, out: "0")) == true)
    #expect(parse?(ShellResult(status: 0, out: "1")) == false)
  }

  @Test
  func testDefaultMenuMigration() {
    #expect(AppSettings.migratedPins(nil) == Catalog.defaultPinned)
    #expect(AppSettings.migratedPins(Catalog.versionTwoDefaultPinned) == Catalog.defaultPinned)
    #expect(
      AppSettings.migratedPins(Array(Catalog.versionTwoDefaultPinned.reversed()))
        == Array(Catalog.versionTwoDefaultPinned.reversed()))
    #expect(AppSettings.migratedPins(Catalog.previousDefaultPinned) == Catalog.defaultPinned)
    #expect(
      AppSettings.migratedPins(Catalog.previousDefaultPinned + ["stageStripAutohide", "trueTone"])
        == Catalog.defaultPinned)
    #expect(AppSettings.migratedPins(["capsLockEscape"]) == Catalog.defaultPinned)
  }

  @Test
  func testCustomMenuMigrationPreservesOrderAndIntentionalEmptyMenu() {
    #expect(
      AppSettings.migratedPins(["wifi", "capsLockEscape", "darkMode", "wifi"]) == [
        "wifi", "darkMode",
      ])
    #expect(AppSettings.migratedPins([]) == [])
  }

  @Test
  func testBooleanArgumentsAreExplicit() {
    for value in ["1", "true", "ON", "yes", " true "] {
      #expect(CLI.parseBoolean(value) == true)
    }
    for value in ["0", "false", "OFF", "no", " false "] {
      #expect(CLI.parseBoolean(value) == false)
    }
    for value in ["banana", "", "2", "truth", "of"] { #expect(CLI.parseBoolean(value) == nil) }
  }

  @Test
  func testInvalidCLIInputIsRejectedBeforeAnyWrite() {
    #expect(CLI.set("darkMode", "banana") == 2)
    #expect(CLI.set("capsLockEscape", "1") == 2)
  }

  @Test
  func testArgumentErrorsReportUsageExitCodeInsteadOfStartingTheApp() {
    #expect(CLI.argumentError("--get needs a setting id.") == 2)
  }

  @Test
  func testCLIRefusesProcessLocalKeepAwake() {
    #expect(CLI.get("keepAwake") == 3)
    #expect(CLI.set("keepAwake", "1") == 3)
    #expect(CLI.set("keepAwake", "0") == 3)
  }

  @Test
  func testUnavailableReadBackIsAnErrorForEitherRequestedValue() throws {
    let spec = try #require(Catalog.byID["wifi"])
    for requested in [false, true] {
      let state = ToggleState(isOn: requested, supported: false, stale: false)
      #expect(ToggleEngine.verificationError(spec, requested: requested, actual: state) != nil)
    }
  }

  @Test
  func testVerificationAcceptsOnlyMatchingReadableState() throws {
    let spec = try #require(Catalog.byID["wifi"])
    let state = ToggleState(isOn: true, stale: false)
    #expect(ToggleEngine.verificationError(spec, requested: true, actual: state) == nil)
    #expect(ToggleEngine.verificationError(spec, requested: false, actual: state) != nil)
  }

  @Test
  func testFailedCommandsCannotBeParsedAsValidState() {
    #expect(Parse.truthy(ShellResult(status: 1, out: "true")) == nil)
    #expect(Parse.says("on", negative: "off")(ShellResult(status: 1, out: "on")) == nil)
    #expect(Parse.pmsetOptional(ShellResult(status: 0, out: "")) == nil)
  }

  @Test
  func testShellSeparatesOutputAndPreservesExitStatus() {
    let result = Shell.run("printf output; printf problem >&2; exit 7")
    #expect(result.out == "output")
    #expect(result.err == "problem")
    #expect(result.status == 7)
  }

  @Test
  func testShellDrainsMoreThanPipeCapacity() {
    let result = Shell.run("/usr/bin/head -c 262144 /dev/zero", timeout: 3)
    #expect(result.status == 0)
    #expect(result.out.utf8.count == 262144)
  }

  @Test
  func testDeadlineIncludesPipesHeldByBackgroundDescendant() {
    let start = ProcessInfo.processInfo.systemUptime
    let result = Shell.run("/bin/sleep 2 & printf done", timeout: 0.1)
    #expect(result.status == -2)
    #expect(ProcessInfo.processInfo.systemUptime - start < 0.8)
  }

  @Test
  func testDeadlineStillAppliesAfterOutputDescriptorsClose() {
    let start = ProcessInfo.processInfo.systemUptime
    let result = Shell.run("exec 1>&- 2>&-; /bin/sleep 2", timeout: 0.1)
    #expect(result.status == -2)
    #expect(ProcessInfo.processInfo.systemUptime - start < 0.8)
  }

  @Test
  func testConcurrentCommandsDoNotHoldOtherCommandsPipesOpen() async {
    let results = await withTaskGroup(of: ShellResult.self) { group in
      for i in 0..<12 {
        group.addTask { Shell.run("printf \(i)", timeout: 1) }
      }
      var values: [ShellResult] = []
      for await value in group { values.append(value) }
      return values
    }
    #expect(results.count == 12)
    #expect(results.allSatisfy { $0.status == 0 })
    #expect(Set(results.map(\.out)) == Set((0..<12).map(String.init)))
  }

  @Test
  func testKeepAwakeEnableIsIdempotentAndDisableReleasesBothAssertions() {
    let driver = FakePowerDriver()
    let controller = KeepAwakeController(driver: driver)
    #expect(!(controller.isOn))
    #expect(controller.set(true) == nil)
    #expect(controller.set(true) == nil)
    #expect(driver.active.count == 2)
    #expect(controller.set(false) == nil)
    #expect(!(controller.isOn))
    #expect(driver.active.isEmpty)
  }

  @Test
  func testKeepAwakeRollsBackPartialCreationFailure() {
    let driver = FakePowerDriver(failSecondCreate: true)
    let controller = KeepAwakeController(driver: driver)
    #expect(controller.set(true) != nil)
    #expect(!(controller.isOn))
    #expect(driver.active.isEmpty)
  }

  @Test
  func testKeepAwakeDoesNotReportSuccessAfterFailedRollback() {
    let driver = FakePowerDriver(failSecondCreate: true)
    driver.failRelease = true
    let controller = KeepAwakeController(driver: driver)
    #expect(controller.set(true) != nil)
    #expect(controller.set(true) != nil)
    #expect(driver.active.count == 1)
    driver.failRelease = false
    #expect(controller.set(false) == nil)
  }

  @Test
  func testKeepAwakeRetainsFailedReleasesForRetry() {
    let driver = FakePowerDriver()
    let controller = KeepAwakeController(driver: driver)
    #expect(controller.set(true) == nil)
    driver.failRelease = true
    #expect(controller.set(false) != nil)
    #expect(controller.isOn)
    driver.failRelease = false
    #expect(controller.set(false) == nil)
    #expect(!(controller.isOn))
  }

  @Test
  func testKeepAwakeControllerCleanup() {
    let driver = FakePowerDriver()
    var controller: KeepAwakeController? = KeepAwakeController(driver: driver)
    #expect(controller?.set(true) == nil)
    controller = nil
    #expect(driver.active.isEmpty)
  }
}

/// Access is serialized by KeepAwakeController; tests inspect it after calls finish.
private final class FakePowerDriver: PowerAssertionDriver, @unchecked Sendable {
  var active = Set<IOPMAssertionID>()
  var failRelease = false
  private var nextID: IOPMAssertionID = 0
  private let failSecondCreate: Bool

  init(failSecondCreate: Bool = false) { self.failSecondCreate = failSecondCreate }

  func create(_ type: String) -> IOPMAssertionID? {
    nextID += 1
    if failSecondCreate && nextID == 2 { return nil }
    active.insert(nextID)
    return nextID
  }

  func release(_ id: IOPMAssertionID) -> Bool {
    if failRelease { return false }
    active.remove(id)
    return true
  }
}

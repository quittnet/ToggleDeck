import Foundation
import IOKit.pwr_mgt
import XCTest

@testable import ToggleDeck

final class ToggleDeckTests: XCTestCase {
  func testAllControlsFitInTwoColumnsOnLaptopAndDesktop() async {
    await MainActor.run {
      let items = Category.allCases.flatMap { category -> [DropdownLayout.Item] in
        [.header(category)] + Catalog.all.filter { $0.category == category }.map { .row($0) }
      }
      for size in [CGSize(width: 1280, height: 752), CGSize(width: 1920, height: 1156)] {
        let result = DropdownLayout.pack(items, showDescriptions: false, screenSize: size)
        XCTAssertEqual(result.columns.count, 2)
        XCTAssertFalse(result.overflowed)
        let ids = result.columns.flatMap { $0 }.compactMap { item -> String? in
          if case .row(let spec) = item { return spec.id }
          return nil
        }
        XCTAssertEqual(ids.count, 20)
        XCTAssertEqual(Set(ids), Set(Catalog.defaultPinned))
        for column in result.columns {
          var category: ToggleDeck.Category?
          for item in column {
            switch item {
            case .header(let value): category = value
            case .row(let spec): XCTAssertEqual(spec.category, category)
            }
          }
        }
      }
    }
  }

  func testDescriptionsFitWithoutSplittingCategories() async {
    await MainActor.run {
      let items = Category.allCases.flatMap { category -> [DropdownLayout.Item] in
        [.header(category)] + Catalog.all.filter { $0.category == category }.map { .row($0) }
      }
      let result = DropdownLayout.pack(
        items, showDescriptions: true,
        screenSize: CGSize(width: 1280, height: 752))
      XCTAssertFalse(result.overflowed)
      XCTAssertLessThanOrEqual(result.width, 1280)
      XCTAssertEqual(result.columns.flatMap { $0 }.count, 27)
    }
  }

  func testFlatColumnsPreserveCustomOrder() async {
    await MainActor.run {
      let specs = Array(Catalog.all.reversed())
      let result = DropdownLayout.pack(
        specs.map { .row($0) }, showDescriptions: false,
        screenSize: CGSize(width: 1280, height: 752))
      let ids = result.columns.flatMap { $0 }.map(\.id)
      XCTAssertEqual(ids, specs.map { "r:\($0.id)" })
      XCTAssertFalse(result.overflowed)
    }
  }

  func testSearchAndEmptyLayoutsStayCompact() async {
    await MainActor.run {
      let result = DropdownLayout.pack(
        [.row(Catalog.all[0])], showDescriptions: false,
        screenSize: CGSize(width: 1280, height: 752))
      XCTAssertEqual(result.columns.count, 1)
      XCTAssertEqual(result.width, 360)
      let empty = DropdownLayout.pack([], showDescriptions: false)
      XCTAssertFalse(empty.overflowed)
      XCTAssertEqual(empty.width, 360)
    }
  }

  @MainActor
  func testPreviewChangesStayInMemory() async {
    let first = ToggleEngine.preview()
    let second = ToggleEngine.preview()
    let initial = first.state("wifi").isOn
    await first.set("wifi", on: !initial)
    await first.refreshAll()
    XCTAssertEqual(first.state("wifi").isOn, !initial)
    XCTAssertEqual(second.state("wifi").isOn, initial)
    XCTAssertNil(first.banner)
  }

  func testCuratedCatalogHasOnlyEverydayControls() {
    XCTAssertEqual(Catalog.all.count, 20)
    XCTAssertEqual(Catalog.byID.count, 20)
    XCTAssertEqual(Catalog.defaultPinned.count, 20)
    XCTAssertEqual(Set(Catalog.defaultPinned), Set(Catalog.all.map(\.id)))
    for id in Catalog.defaultPinned { XCTAssertNotNil(Catalog.byID[id]) }
    for id in ["capsLockEscape", "autoSpellCheck", "firewall", "remoteLogin", "quarantineWarning"] {
      XCTAssertNil(Catalog.byID[id])
    }
    for category in Category.allCases {
      XCTAssertTrue(Catalog.all.contains { $0.category == category })
    }
  }

  func testNoDuplicateSinglePreferenceControls() {
    var keys = Set<String>()
    for spec in Catalog.all {
      if case .defaults(let backing) = spec.backend {
        XCTAssertTrue(
          keys.insert("\(backing.domain):\(backing.key):\(backing.scope)").inserted, spec.id)
      }
    }
  }

  func testDefaultMenuMigration() {
    XCTAssertEqual(AppSettings.migratedPins(nil), Catalog.defaultPinned)
    XCTAssertEqual(AppSettings.migratedPins(Catalog.previousDefaultPinned), Catalog.defaultPinned)
    XCTAssertEqual(
      AppSettings.migratedPins(Catalog.previousDefaultPinned + ["stageStripAutohide", "trueTone"]),
      Catalog.defaultPinned)
    XCTAssertEqual(AppSettings.migratedPins(["capsLockEscape"]), Catalog.defaultPinned)
  }

  func testCustomMenuMigrationPreservesOrderAndIntentionalEmptyMenu() {
    XCTAssertEqual(
      AppSettings.migratedPins(["wifi", "capsLockEscape", "darkMode", "wifi"]),
      ["wifi", "darkMode"])
    XCTAssertEqual(AppSettings.migratedPins([]), [])
  }

  func testBooleanArgumentsAreExplicit() {
    for value in ["1", "true", "ON", "yes", " true "] {
      XCTAssertEqual(CLI.parseBoolean(value), true)
    }
    for value in ["0", "false", "OFF", "no", " false "] {
      XCTAssertEqual(CLI.parseBoolean(value), false)
    }
    for value in ["banana", "", "2", "truth", "of"] { XCTAssertNil(CLI.parseBoolean(value)) }
  }

  func testInvalidCLIInputIsRejectedBeforeAnyWrite() {
    XCTAssertEqual(CLI.set("darkMode", "banana"), 2)
    XCTAssertEqual(CLI.set("capsLockEscape", "1"), 2)
  }

  func testArgumentErrorsReportUsageExitCodeInsteadOfStartingTheApp() {
    XCTAssertEqual(CLI.argumentError("--get needs a setting id."), 2)
  }

  func testCLIRefusesProcessLocalKeepAwake() {
    XCTAssertEqual(CLI.get("keepAwake"), 3)
    XCTAssertEqual(CLI.set("keepAwake", "1"), 3)
    XCTAssertEqual(CLI.set("keepAwake", "0"), 3)
  }

  func testUnavailableReadBackIsAnErrorForEitherRequestedValue() throws {
    let spec = try XCTUnwrap(Catalog.byID["wifi"])
    for requested in [false, true] {
      let state = ToggleState(isOn: requested, supported: false, stale: false)
      XCTAssertNotNil(ToggleEngine.verificationError(spec, requested: requested, actual: state))
    }
  }

  func testVerificationAcceptsOnlyMatchingReadableState() throws {
    let spec = try XCTUnwrap(Catalog.byID["wifi"])
    let state = ToggleState(isOn: true, stale: false)
    XCTAssertNil(ToggleEngine.verificationError(spec, requested: true, actual: state))
    XCTAssertNotNil(ToggleEngine.verificationError(spec, requested: false, actual: state))
  }

  func testFailedCommandsCannotBeParsedAsValidState() {
    XCTAssertNil(Parse.truthy(ShellResult(status: 1, out: "true")))
    XCTAssertNil(Parse.says("on", negative: "off")(ShellResult(status: 1, out: "on")))
    XCTAssertNil(Parse.pmsetOptional(ShellResult(status: 0, out: "")))
  }

  func testShellSeparatesOutputAndPreservesExitStatus() {
    let result = Shell.run("printf output; printf problem >&2; exit 7")
    XCTAssertEqual(result.out, "output")
    XCTAssertEqual(result.err, "problem")
    XCTAssertEqual(result.status, 7)
  }

  func testShellDrainsMoreThanPipeCapacity() {
    let result = Shell.run("/usr/bin/head -c 262144 /dev/zero", timeout: 3)
    XCTAssertEqual(result.status, 0)
    XCTAssertEqual(result.out.utf8.count, 262144)
  }

  func testDeadlineIncludesPipesHeldByBackgroundDescendant() {
    let start = ProcessInfo.processInfo.systemUptime
    let result = Shell.run("/bin/sleep 2 & printf done", timeout: 0.1)
    XCTAssertEqual(result.status, -2)
    XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 0.8)
  }

  func testDeadlineStillAppliesAfterOutputDescriptorsClose() {
    let start = ProcessInfo.processInfo.systemUptime
    let result = Shell.run("exec 1>&- 2>&-; /bin/sleep 2", timeout: 0.1)
    XCTAssertEqual(result.status, -2)
    XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 0.8)
  }

  func testConcurrentCommandsDoNotHoldOtherCommandsPipesOpen() async {
    let results = await withTaskGroup(of: ShellResult.self) { group in
      for i in 0..<12 {
        group.addTask { Shell.run("printf \(i)", timeout: 1) }
      }
      var values: [ShellResult] = []
      for await value in group { values.append(value) }
      return values
    }
    XCTAssertEqual(results.count, 12)
    XCTAssertTrue(results.allSatisfy { $0.status == 0 })
    XCTAssertEqual(Set(results.map(\.out)), Set((0..<12).map(String.init)))
  }

  func testKeepAwakeEnableIsIdempotentAndDisableReleasesBothAssertions() {
    let driver = FakePowerDriver()
    let controller = KeepAwakeController(driver: driver)
    XCTAssertFalse(controller.isOn)
    XCTAssertNil(controller.set(true))
    XCTAssertNil(controller.set(true))
    XCTAssertEqual(driver.active.count, 2)
    XCTAssertNil(controller.set(false))
    XCTAssertFalse(controller.isOn)
    XCTAssertTrue(driver.active.isEmpty)
  }

  func testKeepAwakeRollsBackPartialCreationFailure() {
    let driver = FakePowerDriver(failSecondCreate: true)
    let controller = KeepAwakeController(driver: driver)
    XCTAssertNotNil(controller.set(true))
    XCTAssertFalse(controller.isOn)
    XCTAssertTrue(driver.active.isEmpty)
  }

  func testKeepAwakeDoesNotReportSuccessAfterFailedRollback() {
    let driver = FakePowerDriver(failSecondCreate: true)
    driver.failRelease = true
    let controller = KeepAwakeController(driver: driver)
    XCTAssertNotNil(controller.set(true))
    XCTAssertNotNil(controller.set(true))
    XCTAssertEqual(driver.active.count, 1)
    driver.failRelease = false
    XCTAssertNil(controller.set(false))
  }

  func testKeepAwakeRetainsFailedReleasesForRetry() {
    let driver = FakePowerDriver()
    let controller = KeepAwakeController(driver: driver)
    XCTAssertNil(controller.set(true))
    driver.failRelease = true
    XCTAssertNotNil(controller.set(false))
    XCTAssertTrue(controller.isOn)
    driver.failRelease = false
    XCTAssertNil(controller.set(false))
    XCTAssertFalse(controller.isOn)
  }

  func testKeepAwakeControllerCleanup() {
    let driver = FakePowerDriver()
    var controller: KeepAwakeController? = KeepAwakeController(driver: driver)
    XCTAssertNil(controller?.set(true))
    controller = nil
    XCTAssertTrue(driver.active.isEmpty)
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

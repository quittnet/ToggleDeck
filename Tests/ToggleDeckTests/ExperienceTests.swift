import Foundation
import Testing

@testable import ToggleDeck

@Suite(.serialized)
struct ExperienceTests {
  @Test
  func testSearchMatchesWordsInAnyOrderAndPunctuation() {
    for query in ["wifi", "WI-FI", "wi fi", "  wífi  "] {
      #expect(SettingSearch.results(in: Catalog.all, query: query).first?.id == "wifi")
    }
    #expect(
      SettingSearch.results(in: Catalog.all, query: "finder hidden").map(\.id) == [
        "showHiddenFiles"
      ])
    #expect(
      SettingSearch.results(in: Catalog.all, query: "hidden finder").map(\.id) == [
        "showHiddenFiles"
      ])
    #expect(SettingSearch.results(in: Catalog.all, query: "   ").map(\.id) == Catalog.all.map(\.id))
    #expect(SettingSearch.results(in: Catalog.all, query: "not-a-setting-zzz").isEmpty)
  }

  @Test
  func testExactTitleRanksBeforeDescriptionMatch() {
    #expect(
      SettingSearch.results(in: Catalog.all, query: "Screenshot Preview").first?.id
        == "screenshotThumbnail")
  }

  @Test
  func testFiltersNeverReportUnknownValuesAsOff() {
    let unknown = ToggleState()
    #expect(!(ControlFilter.on.includes(unknown)))
    #expect(!(ControlFilter.off.includes(unknown)))
    #expect(!(ControlFilter.unavailable.includes(unknown)))
    let unsupported = ToggleState(supported: false, stale: false)
    #expect(ControlFilter.unavailable.includes(unsupported))
    #expect(!(ControlFilter.off.includes(unsupported)))
    #expect(ControlFilter.on.includes(ToggleState(isOn: true, stale: false)))
    #expect(ControlFilter.off.includes(ToggleState(stale: false)))
  }

  @Test
  func testNavigationMovesAcrossUnevenColumnsAndStopsAtEdges() {
    let columns = [["a", "b", "c"], ["d", "e"]]
    #expect(DropdownNavigation.target(in: columns, current: nil, direction: .down) == "a")
    #expect(DropdownNavigation.target(in: columns, current: "c", direction: .right) == "e")
    #expect(DropdownNavigation.target(in: columns, current: "e", direction: .left) == "b")
    #expect(DropdownNavigation.target(in: columns, current: "c", direction: .down) == "d")
    #expect(DropdownNavigation.target(in: columns, current: "a", direction: .up) == "a")
    #expect(DropdownNavigation.target(in: [], current: nil, direction: .down) == nil)
  }

  @MainActor
  @Test
  func testPreviewPreferencesAreIndependentAndCannotChangeLoginConfiguration() {
    let loginBefore = LoginItem.isEnabled
    let first = AppSettings.preview()
    let second = AppSettings.preview()
    first.pinned = ["wifi"]
    first.showDescriptions = true
    first.launchAtLogin = !loginBefore
    #expect(second.pinned == Catalog.defaultPinned)
    #expect(!second.showDescriptions)
    #expect(LoginItem.isEnabled == loginBefore)
  }

  @MainActor
  @Test
  func testMenuReorderingUsesCustomOrderAndPersists() {
    let suite = "com.user.toggledeck.tests.\(UUID().uuidString)"
    let store = UserDefaults(suiteName: suite)!
    defer { store.removePersistentDomain(forName: suite) }
    let settings = AppSettings(store: store)
    settings.pinned = ["wifi", "darkMode", "keepAwake"]
    settings.movePin("keepAwake", by: -1)
    #expect(settings.pinned == ["wifi", "keepAwake", "darkMode"])
    #expect(!(settings.groupDropdown))
    settings.movePinned(from: IndexSet(integer: 0), to: 3)
    #expect(settings.pinned == ["keepAwake", "darkMode", "wifi"])
    #expect(AppSettings(store: store).pinned == settings.pinned)
    settings.movePin("keepAwake", by: -1)
    #expect(settings.pinned.first == "keepAwake")
  }

  @MainActor
  @Test
  func testTinyAndShortScreensReserveFeedbackSpace() {
    let items = Catalog.all.map { DropdownLayout.Item.row($0) }
    for size in [CGSize(width: 280, height: 560), CGSize(width: 1280, height: 480)] {
      let result = DropdownLayout.pack(
        items, showDescriptions: true, extraChrome: 158, screenSize: size)
      #expect(result.width <= size.width)
      #expect(result.overflowed)
      #expect(Set(result.columns.flatMap { $0 }.map(\.id)) == Set(items.map(\.id)))
    }
  }

  @Test
  func testBooleanParsersRejectAmbiguousAndMalformedOutput() {
    for value in ["10", "online", "falsehood", "yesterday", "-1", "1 0"] {
      #expect(Parse.truthy(ShellResult(status: 0, out: value)) == nil)
    }
    #expect(Parse.truthy(ShellResult(status: 0, out: "enabled")) == true)
    #expect(Parse.truthy(ShellResult(status: 0, out: "disabled")) == false)
    #expect(Parse.pmsetOptional(ShellResult(status: 0, out: "unexpected")) == nil)
  }

  @MainActor
  @Test
  func testTimedAwakeExpiresAndIndefiniteSessionCancelsOldTimer() async throws {
    let engine = ToggleEngine.preview()
    await engine.keepAwake(for: 0.02)
    #expect(engine.keepAwakeUntil != nil)
    try await Task.sleep(for: .milliseconds(100))
    #expect(!(engine.state("keepAwake").isOn))
    #expect(engine.keepAwakeUntil == nil)
    await engine.keepAwake(for: 0.02)
    await engine.keepAwake(for: nil)
    try await Task.sleep(for: .milliseconds(100))
    #expect(engine.state("keepAwake").isOn)
    #expect(engine.keepAwakeUntil == nil)
    await engine.set("keepAwake", on: false)
    #expect(!(engine.state("keepAwake").isOn))
  }

  @MainActor
  @Test
  func testChangingAwakeDurationReplacesItsDeadline() async throws {
    let engine = ToggleEngine.preview()
    await engine.keepAwake(for: 0.02)
    await engine.keepAwake(for: 10)
    try await Task.sleep(for: .milliseconds(100))
    #expect(engine.state("keepAwake").isOn)
    await engine.set("keepAwake", on: false)
    #expect(engine.keepAwakeUntil == nil)
    await engine.keepAwake(for: -1)
    await engine.keepAwake(for: .infinity)
    #expect(!(engine.state("keepAwake").isOn))
  }

  @MainActor
  @Test
  func testOldRefreshCannotOverwriteCompletedWrite() async {
    await checkRefreshRace(single: false)
    await checkRefreshRace(single: true)
  }

  @MainActor
  private func checkRefreshRace(single: Bool) async {
    let backend = PausedReader()
    let engine = ToggleEngine(
      reader: { spec, verifying in await backend.read(spec, verifying: verifying) },
      writer: { spec, on in await backend.write(spec, on: on) }, verificationDelay: 0)
    await engine.refreshAll()
    await backend.pauseNextWiFiRead()
    let oldRefresh = Task {
      if single { await engine.refresh("wifi") } else { await engine.refreshAll() }
    }
    await backend.waitUntilPaused()
    await engine.set("wifi", on: true)
    #expect(engine.state("wifi").isOn)
    await backend.release()
    await oldRefresh.value
    #expect(engine.state("wifi").isOn)
    #expect(!(engine.state("wifi").busy))
  }

  @Test
  func testMissingPreferenceIsDifferentFromFailedOrHardwareRead() {
    let missing = ShellResult(status: 1, out: "", err: "The domain/default pair does not exist")
    #expect(
      ToggleEngine.isMissingPreference(
        command: "/usr/bin/defaults read com.apple.WindowManager key", result: missing))
    #expect(!ToggleEngine.isMissingPreference(command: "/usr/bin/pmset -g", result: missing))
    #expect(
      !ToggleEngine.isMissingPreference(
        command: "/usr/bin/defaults read domain key",
        result: ShellResult(status: -2, out: "", err: "does not exist")))
    #expect(
      !ToggleEngine.isMissingPreference(
        command: "/usr/bin/defaults read domain key",
        result: ShellResult(status: 1, out: "", err: "Operation not permitted")))
  }

  @MainActor
  @Test
  func testFailedWriteRollsBackAndSuccessfulRetryClearsFeedback() async {
    let backend = PausedReader()
    let engine = ToggleEngine(
      reader: { spec, verifying in await backend.read(spec, verifying: verifying) },
      writer: { spec, on in await backend.write(spec, on: on) }, verificationDelay: 0)
    await engine.refreshAll()
    await backend.failWrites(true)
    await engine.set("wifi", on: true)
    #expect(!engine.state("wifi").isOn)
    #expect(!engine.state("wifi").busy)
    #expect(engine.state("wifi").error != nil)
    #expect(engine.banner != nil)
    await backend.failWrites(false)
    await engine.set("wifi", on: true)
    #expect(engine.state("wifi").isOn)
    #expect(engine.state("wifi").error == nil)
    #expect(engine.banner == nil)
  }

  @MainActor
  @Test
  func testUnreadStateCannotBeWritten() async {
    let backend = PausedReader()
    let engine = ToggleEngine(
      reader: { spec, verifying in await backend.read(spec, verifying: verifying) },
      writer: { spec, on in await backend.write(spec, on: on) }, verificationDelay: 0)
    await engine.set("wifi", on: true)
    let count = await backend.writeCount
    #expect(count == 0)
    #expect(engine.state("wifi").stale)
  }
}

private actor PausedReader {
  private var value = false
  private var pause = false
  private var failure = false
  func failWrites(_ fail: Bool) { failure = fail }
  private var suspended: CheckedContinuation<Void, Never>?
  private var waiting: [CheckedContinuation<Void, Never>] = []
  private(set) var writeCount = 0

  func pauseNextWiFiRead() { pause = true }
  func waitUntilPaused() async {
    if suspended != nil { return }
    await withCheckedContinuation { waiting.append($0) }
  }
  func release() {
    suspended?.resume()
    suspended = nil
  }
  func read(_ spec: ToggleSpec, verifying: Bool) async -> ToggleState {
    let captured = value
    if spec.id == "wifi", pause, !verifying {
      pause = false
      await withCheckedContinuation { continuation in
        suspended = continuation
        for waiter in waiting { waiter.resume() }
        waiting.removeAll()
      }
    }
    return ToggleState(isOn: spec.id == "wifi" ? captured : false, stale: false)
  }
  func write(_ spec: ToggleSpec, on: Bool) -> String? {
    writeCount += 1
    if failure { return "macOS blocked the change." }
    if spec.id == "wifi" { value = on }
    return nil
  }
}

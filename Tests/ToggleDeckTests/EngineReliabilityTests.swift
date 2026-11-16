import Testing

@testable import ToggleDeck

struct EngineReliabilityTests {
  // MARK: Missing preference keys

  @Test
  func missingDesktopIconsKeyReadsAsTheSystemDefault() throws {
    let spec = try #require(Catalog.byID["showDesktopIcons"])
    let missing = ShellResult(
      status: 1, out: "",
      err:
        "Error: Could not find key 'StandardHideDesktopIcons' in domain 'com.apple.WindowManager'.")
    let state = ToggleEngine.shellState(spec, result: missing)
    #expect(state.supported)
    #expect(!state.stale)
    #expect(state.isOn == spec.systemDefault)
    // A write that cannot be read back is still unconfirmed.
    #expect(!ToggleEngine.shellState(spec, result: missing, verifyingWrite: true).supported)
  }

  // MARK: Low Power Mode

  @Test
  func lowPowerModeReadsTheSettingsInUse() throws {
    let spec = try #require(Catalog.byID["lowPowerMode"])
    guard case .shell(let read, let on, let off, _) = spec.backend else {
      Issue.record("Low Power Mode is expected to be shell backed")
      return
    }
    #expect(
      read == "/usr/bin/pmset -g 2>/dev/null | /usr/bin/awk '$1==\"lowpowermode\"{print $2; exit}'")
    #expect(!read.contains("custom"))
    #expect(on == "/usr/bin/pmset -a lowpowermode 1")
    #expect(off == "/usr/bin/pmset -a lowpowermode 0")
  }

  @Test
  func pmsetOptionalMapsInUseValues() {
    #expect(Parse.pmsetOptional(ShellResult(status: 0, out: "0\n")) == false)
    #expect(Parse.pmsetOptional(ShellResult(status: 0, out: "1\n")) == true)
    #expect(Parse.pmsetOptional(ShellResult(status: 0, out: "")) == nil)
    #expect(Parse.pmsetOptional(ShellResult(status: 1, out: "1")) == nil)
  }

  // MARK: Mute Sound

  @Test
  func muteOnAnOutputWithoutMuteControlIsUnavailable() throws {
    let spec = try #require(Catalog.byID["muteOutput"])
    let state = ToggleEngine.shellState(
      spec, result: ShellResult(status: 0, out: "missing value\n"))
    #expect(!state.supported)
    #expect(ToggleEngine.shellState(spec, result: ShellResult(status: 0, out: "true\n")).isOn)
    let off = ToggleEngine.shellState(spec, result: ShellResult(status: 0, out: "false\n"))
    #expect(off.supported && !off.isOn)
  }

  // MARK: Bluetooth settling

  @Test
  func bluetoothWaitReturnsAsSoonAsTheRadioMatches() {
    var reads: [Bool?] = [nil, false, true, true]
    var sleeps = 0
    let applied = Bridges.waitForBluetooth(
      true, read: { reads.removeFirst() }, sleep: { _ in sleeps += 1 })
    #expect(applied)
    #expect(sleeps == 3)
    #expect(reads.count == 1)
  }

  @Test
  func bluetoothWaitGivesUpAfterItsAttempts() {
    var readCount = 0
    var slept: UInt32 = 0
    let applied = Bridges.waitForBluetooth(
      false,
      read: {
        readCount += 1
        return readCount.isMultiple(of: 2) ? nil : true
      }, sleep: { slept += $0 })
    #expect(!applied)
    #expect(readCount == 8)
    #expect(slept == 8 * 300_000)
  }

  // MARK: Refresh coalescing

  @MainActor
  @Test
  func explicitRefreshDuringAutomaticPassStillClearsTheFailure() async {
    let backend = HeldReader()
    let engine = ToggleEngine(
      reader: { spec, verifying in await backend.read(spec, verifying: verifying) },
      writer: { spec, on in await backend.write(spec, on: on) }, verificationDelay: 0)
    await engine.refreshAll()
    await backend.failWrites(true)
    await engine.set("wifi", on: true)
    #expect(engine.state("wifi").error != nil)
    #expect(engine.banner != nil)

    await backend.holdNextWiFiRead()
    let automatic = Task { await engine.refreshAll() }
    await backend.waitUntilHeld()
    #expect(engine.isRefreshing)
    // Returns at once; the request is queued behind the running pass.
    await engine.refreshAll(clearError: true)
    await engine.refreshAll(clearError: true)
    #expect(engine.isRefreshing)
    await backend.release()
    await automatic.value

    #expect(!engine.isRefreshing)
    #expect(!engine.state("wifi").isOn)
    #expect(engine.state("wifi").error == nil)
    #expect(engine.banner == nil)
    // Two queued requests coalesce into one follow-up pass.
    let wifiReads = await backend.wifiReads
    #expect(wifiReads == 3)
  }

  @MainActor
  @Test
  func automaticRefreshDuringAPassIsStillDropped() async {
    let backend = HeldReader()
    let engine = ToggleEngine(
      reader: { spec, verifying in await backend.read(spec, verifying: verifying) },
      writer: { spec, on in await backend.write(spec, on: on) }, verificationDelay: 0)
    await engine.refreshAll()
    await backend.failWrites(true)
    await engine.set("wifi", on: true)

    await backend.holdNextWiFiRead()
    let automatic = Task { await engine.refreshAll() }
    await backend.waitUntilHeld()
    await engine.refreshAll()
    await backend.release()
    await automatic.value

    #expect(engine.state("wifi").error != nil)
    #expect(engine.banner != nil)
    let wifiReads = await backend.wifiReads
    #expect(wifiReads == 2)
  }
}

private actor HeldReader {
  private var value = false
  private var hold = false
  private var failure = false
  private var suspended: CheckedContinuation<Void, Never>?
  private var waiting: [CheckedContinuation<Void, Never>] = []
  private(set) var wifiReads = 0

  func failWrites(_ fail: Bool) { failure = fail }
  func holdNextWiFiRead() { hold = true }
  func waitUntilHeld() async {
    if suspended != nil { return }
    await withCheckedContinuation { waiting.append($0) }
  }
  func release() {
    suspended?.resume()
    suspended = nil
  }
  func read(_ spec: ToggleSpec, verifying: Bool) async -> ToggleState {
    let captured = value
    if spec.id == "wifi", !verifying {
      wifiReads += 1
      if hold {
        hold = false
        await withCheckedContinuation { continuation in
          suspended = continuation
          for waiter in waiting { waiter.resume() }
          waiting.removeAll()
        }
      }
    }
    return ToggleState(isOn: spec.id == "wifi" ? captured : false, stale: false)
  }
  func write(_ spec: ToggleSpec, on: Bool) -> String? {
    if failure { return "macOS blocked the change." }
    if spec.id == "wifi" { value = on }
    return nil
  }
}

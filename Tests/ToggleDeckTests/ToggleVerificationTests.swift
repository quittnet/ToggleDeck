import Testing

@testable import ToggleDeck

struct ToggleVerificationTests {
  @Test
  func canceledVerificationCannotConfirmAnOffRequest() async {
    let spec = Catalog.byID["autoCorrect"]!
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return await ToggleEngine.verify(spec, requested: false)
    }
    let state = await task.value
    #expect(ToggleEngine.verificationError(spec, requested: false, actual: state) != nil)
  }

  @Test
  func delayedWriteConvergesWithoutRepeatingWrite() async {
    let backend = SettlingToggle(readsBeforeSuccess: 3)
    let spec = Catalog.byID["autoCorrect"]!
    let state = await ToggleEngine.verify(
      spec, requested: true, delay: 0,
      reader: { _, _ in await backend.read() })
    #expect(state.supported && state.isOn)
    #expect(await backend.readCount == 4)
  }

  @Test
  func unreadableFirstReadCanRecover() async {
    let backend = SettlingToggle(readsBeforeSuccess: 1, unreadable: true)
    let state = await ToggleEngine.verify(
      Catalog.byID["autoCorrect"]!, requested: true, delay: 0,
      reader: { _, _ in await backend.read() })
    #expect(state.supported && state.isOn)
    #expect(await backend.readCount == 2)
  }

  @MainActor
  @Test
  func unreadableVerificationRetainsRetryableControl() async {
    let backend = SettlingToggle(readsBeforeSuccess: 100, unreadable: true)
    let engine = ToggleEngine(
      reader: { _, verifying in
        verifying ? await backend.read() : ToggleState(isOn: false, stale: false)
      }, writer: { _, _ in await backend.write() }, verificationDelay: 0)
    await engine.refresh("autoCorrect")
    await engine.set("autoCorrect", on: true)
    #expect(engine.state("autoCorrect").supported)
    #expect(!engine.state("autoCorrect").isOn)
    #expect(!engine.state("autoCorrect").busy)
    #expect(engine.state("autoCorrect").error != nil)
    #expect(await backend.readCount == 12)
    await engine.set("autoCorrect", on: true)
    #expect(await backend.writeCount == 2)
  }

  @Test
  func permanentRejectionStopsPolling() async {
    let backend = SettlingToggle(readsBeforeSuccess: 100)
    let spec = Catalog.byID["autoCorrect"]!
    let state = await ToggleEngine.verify(
      spec, requested: true, delay: 0,
      reader: { _, _ in await backend.read() })
    #expect(ToggleEngine.verificationError(spec, requested: true, actual: state) != nil)
    #expect(await backend.readCount == 12)
  }
}

private actor SettlingToggle {
  let readsBeforeSuccess: Int
  let unreadable: Bool
  private(set) var readCount = 0
  private(set) var writeCount = 0

  init(readsBeforeSuccess: Int, unreadable: Bool = false) {
    self.readsBeforeSuccess = readsBeforeSuccess
    self.unreadable = unreadable
  }

  func read() -> ToggleState {
    readCount += 1
    let settled = readCount > readsBeforeSuccess
    return ToggleState(isOn: settled, supported: settled || !unreadable, stale: false)
  }

  func write() -> String? {
    writeCount += 1
    return nil
  }
}

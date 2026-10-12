import Foundation
import Testing

@testable import ToggleDeck

@Suite(.serialized)
struct CursorColorTests {
  @Test
  func testComponentDictionaryAcceptsNumbersStringsAndInclusiveBoundaries() {
    let numeric = CursorRGB(components: [
      "red": NSNumber(value: 0.25), "green": 0.5, "blue": 1, "alpha": 0,
      "unused": "ignored",
    ])
    #expect(numeric == CursorRGB(red: 0.25, green: 0.5, blue: 1, alpha: 0))
    let strings = CursorRGB(components: [
      "red": "0", "green": "0.25", "blue": "1", "alpha": "1",
    ])
    #expect(strings == CursorRGB(red: 0, green: 0.25, blue: 1))
  }

  @Test
  func testComponentDictionaryRejectsMissingMalformedAndBooleanValues() {
    let valid: [String: Any] = ["red": 0, "green": 0.5, "blue": 1, "alpha": 1]
    for key in ["red", "green", "blue", "alpha"] {
      var missing = valid
      missing.removeValue(forKey: key)
      #expect(CursorRGB(components: missing) == nil)
      for value: Any in [true, false, NSNumber(value: true), "blue", NSNull(), [0.5]] {
        var malformed = valid
        malformed[key] = value
        #expect(CursorRGB(components: malformed) == nil)
      }
    }
  }

  @Test
  func testComponentDictionaryRejectsNonfiniteAndOutOfRangeChannels() {
    let valid: [String: Any] = ["red": 0, "green": 0.5, "blue": 1, "alpha": 1]
    for key in ["red", "green", "blue", "alpha"] {
      for value: Any in [
        Double.nan, Double.infinity, -Double.infinity, -0.001, 1.001,
        "nan", "inf", "-inf", "-0.001", "1.001",
      ] {
        var malformed = valid
        malformed[key] = value
        #expect(CursorRGB(components: malformed) == nil)
      }
    }
    #expect(!CursorRGB(red: .nan, green: 0, blue: 0).isValid)
    #expect(!CursorRGB(red: 0, green: 0, blue: 0, alpha: 1.01).isValid)
  }

  @Test
  func testPresetDefaultsAndMatchingTolerance() {
    #expect(CursorPreset.standard.colors == .standard)
    #expect(CursorColors.standard.fill == .black)
    #expect(CursorColors.standard.outline == .white)
    #expect(!CursorColors.standard.customized)
    for preset in CursorPreset.allCases {
      #expect(preset.colors.isValid)
      #expect(CursorPreset.matching(preset.colors) == preset)
      #expect(preset.colors.customized == (preset != .standard))
    }
    let blue = CursorPreset.blue.colors
    let nearBlue = CursorColors(
      fill: CursorRGB(red: blue.fill.red + 0.00009, green: blue.fill.green, blue: blue.fill.blue),
      outline: blue.outline, customized: true)
    #expect(CursorPreset.matching(nearBlue) == .blue)
    let differentBlue = CursorColors(
      fill: CursorRGB(red: blue.fill.red + 0.00011, green: blue.fill.green, blue: blue.fill.blue),
      outline: blue.outline, customized: true)
    #expect(CursorPreset.matching(differentBlue) == nil)
    let transparentBlue = CursorColors(
      fill: CursorRGB(
        red: blue.fill.red, green: blue.fill.green, blue: blue.fill.blue, alpha: 0.8),
      outline: blue.outline, customized: true)
    #expect(CursorPreset.matching(transparentBlue) == nil)
    #expect(!blue.matches(CursorColors(fill: blue.fill, outline: .black, customized: true)))
  }

  @MainActor
  @Test
  func testCustomSelectionNameAndPreviewIsolation() async {
    let backend = CursorColorBackend()
    let first = CursorColorController(
      preview: true, reader: { await backend.read() }, writer: { await backend.write($0) })
    let second = CursorColorController.preview(colors: CursorPreset.green.colors)
    let custom = CursorColors(
      fill: CursorRGB(red: 0.3, green: 0.4, blue: 0.5),
      outline: CursorRGB(red: 0.8, green: 0.7, blue: 0.6), customized: true)
    await first.refresh()
    await first.apply(custom)
    #expect(first.palettes.savedColors.count == 1)
    #expect(first.palettes.matching(custom)?.colors == custom)
    #expect(first.selectionName == first.palettes.matching(custom)?.name)
    first.palettes.save(custom, name: "Preview Saved Colors")
    #expect(first.selectionName == "Preview Saved Colors")
    #expect(first.colors == custom)
    #expect(first.available)
    #expect(!first.isLoading)
    #expect(!first.isApplying)
    #expect(second.colors == CursorPreset.green.colors)
    #expect(second.selectionName == "Green")
    #expect(first.palettes !== second.palettes)
    #expect(second.palettes.savedColors.isEmpty)
    #expect(CursorColorController.preview().palettes.savedColors.isEmpty)
    let counts = await backend.counts()
    #expect(counts.reads == 0)
    #expect(counts.writes == 0)
  }

  @MainActor
  @Test
  func testWritesWaitForInitialRead() async {
    let backend = CursorColorBackend()
    let controller = makeController(using: backend)
    #expect(controller.isLoading)
    #expect(!controller.available)
    await controller.apply(CursorPreset.red.colors)
    let before = await backend.counts()
    #expect(before.writes == 0)
    await controller.refresh()
    #expect(!controller.isLoading)
    #expect(!controller.isRefreshing)
    #expect(controller.available)
    #expect(controller.colors == .standard)
    #expect(controller.error == nil)
  }

  @MainActor
  @Test
  func testMissingBackendBecomesAvailableAfterRecovery() async {
    let backend = CursorColorBackend(value: nil)
    let controller = makeController(using: backend)
    await controller.refresh()
    #expect(!controller.available)
    #expect(!controller.isLoading)
    #expect(controller.error != nil)
    await controller.apply(CursorPreset.red.colors)
    let unavailableCounts = await backend.counts()
    #expect(unavailableCounts.writes == 0)
    await backend.setValue(CursorPreset.blue.colors)
    await controller.refresh()
    #expect(controller.available)
    #expect(controller.colors == CursorPreset.blue.colors)
    #expect(controller.error == nil)
    await controller.apply(CursorPreset.red.colors)
    #expect(controller.colors == CursorPreset.red.colors)
    #expect(controller.error == nil)
  }

  @MainActor
  @Test
  func testMalformedReadbackIsUnavailable() async {
    let malformed = CursorColors(
      fill: CursorRGB(red: -0.1, green: 0, blue: 0), outline: .white, customized: true)
    let backend = CursorColorBackend(value: malformed)
    let controller = makeController(using: backend)
    await controller.refresh()
    #expect(!controller.available)
    #expect(controller.colors == .standard)
    #expect(controller.error != nil)
    #expect(!controller.isRefreshing)
  }

  @MainActor
  @Test
  func testSuccessfulApplyUsesVerifiedSystemReadback() async {
    let backend = CursorColorBackend()
    let controller = makeController(using: backend)
    await controller.refresh()
    let requested = CursorPreset.red.colors
    let verified = CursorColors(
      fill: CursorRGB(
        red: requested.fill.red - 0.00004, green: requested.fill.green, blue: requested.fill.blue),
      outline: requested.outline, customized: true)
    await backend.setWriteOverride(verified)
    await controller.apply(requested)
    #expect(controller.colors == verified)
    #expect(controller.colors != requested)
    #expect(controller.error == nil)
    #expect(!controller.isApplying)
    let counts = await backend.counts()
    #expect(counts.reads == 2)
    #expect(counts.writes == 1)
  }

  @MainActor
  @Test
  func testRejectedApplyReportsActualColors() async {
    let backend = CursorColorBackend(value: CursorPreset.green.colors)
    let controller = makeController(using: backend)
    await controller.refresh()
    await backend.setAppliesWrites(false)
    await controller.apply(CursorPreset.red.colors)
    #expect(controller.colors == CursorPreset.green.colors)
    #expect(controller.error != nil)
    #expect(controller.available)
    #expect(!controller.isApplying)
  }

  @MainActor
  @Test
  func testReadbackMustConfirmDefaultCustomizationWasDisabled() async {
    let backend = CursorColorBackend(value: CursorPreset.pink.colors)
    let controller = makeController(using: backend)
    await controller.refresh()
    let stillCustomized = CursorColors(fill: .black, outline: .white, customized: true)
    await backend.setWriteOverride(stillCustomized)
    await controller.apply(.standard)
    #expect(controller.colors == stillCustomized)
    #expect(controller.error != nil)
    #expect(!controller.isApplying)
  }

  @MainActor
  @Test
  func testWriterFailurePreservesColorsAndRetryClearsFeedback() async {
    let backend = CursorColorBackend(value: CursorPreset.blue.colors)
    let controller = makeController(using: backend)
    await controller.refresh()
    await backend.setWriterFailure("The color service rejected this change.")
    await controller.apply(CursorPreset.red.colors)
    #expect(controller.colors == CursorPreset.blue.colors)
    #expect(controller.error == "The color service rejected this change.")
    #expect(!controller.isApplying)
    let failedCounts = await backend.counts()
    #expect(failedCounts.reads == 1)
    #expect(failedCounts.writes == 1)
    await backend.setWriterFailure(nil)
    await controller.apply(CursorPreset.red.colors)
    #expect(controller.colors == CursorPreset.red.colors)
    #expect(controller.error == nil)
    #expect(!controller.isApplying)
  }

  @MainActor
  @Test
  func testAutomaticRefreshPreservesWriteFailureUntilExplicitRefresh() async {
    let original = CursorPreset.blue.colors
    let backend = CursorColorBackend(value: original)
    let controller = makeController(using: backend)
    await controller.refresh()
    let failure = "The color service rejected this change."
    await backend.setWriterFailure(failure)
    await controller.apply(CursorPreset.red.colors)
    #expect(controller.error == failure)
    await controller.refresh(clearError: false)
    #expect(controller.colors == original)
    #expect(controller.error == failure)
    #expect(controller.available)
    #expect(!controller.isRefreshing)
    await controller.refresh()
    #expect(controller.colors == original)
    #expect(controller.error == nil)
    let counts = await backend.counts()
    #expect(counts.reads == 3)
    #expect(counts.writes == 1)
  }

  @MainActor
  @Test
  func testAutomaticRefreshOfExternalColorChangeClearsOldWriteFailure() async {
    let backend = CursorColorBackend(value: CursorPreset.blue.colors)
    let controller = makeController(using: backend)
    await controller.refresh()
    await backend.setWriterFailure("The color service rejected this change.")
    await controller.apply(CursorPreset.red.colors)
    #expect(controller.error != nil)
    #expect(controller.selectionName == "Blue")
    await backend.setValue(CursorPreset.orange.colors)
    await controller.refresh(clearError: false)
    #expect(controller.colors == CursorPreset.orange.colors)
    #expect(controller.selectionName == "Orange")
    #expect(controller.error == nil)
    #expect(controller.available)
    #expect(!controller.isRefreshing)
    let counts = await backend.counts()
    #expect(counts.reads == 2)
    #expect(counts.writes == 1)
  }

  @MainActor
  @Test
  func testUnconfirmedWritePreservesLastKnownColors() async {
    let backend = CursorColorBackend(value: CursorPreset.blue.colors)
    let controller = makeController(using: backend)
    await controller.refresh()
    await backend.setUnavailableAfterWrite(true)
    await controller.apply(CursorPreset.red.colors)
    #expect(controller.colors == CursorPreset.blue.colors)
    #expect(controller.error != nil)
    #expect(!controller.isApplying)
  }

  @MainActor
  @Test
  func testInvalidRequestNeverReachesWriter() async {
    let backend = CursorColorBackend()
    let controller = makeController(using: backend)
    await controller.refresh()
    let invalid = CursorColors(
      fill: CursorRGB(red: 0, green: 0, blue: 0, alpha: .infinity),
      outline: .white, customized: true)
    await controller.apply(invalid)
    #expect(controller.colors == .standard)
    #expect(controller.error != nil)
    #expect(!controller.isApplying)
    let counts = await backend.counts()
    #expect(counts.writes == 0)
    #expect(counts.reads == 1)
  }

  @MainActor
  @Test
  func testBusyApplyIgnoresSecondApplyAndRefresh() async {
    let backend = CursorColorBackend()
    let controller = makeController(using: backend)
    await controller.refresh()
    await backend.pauseNextWrite()
    let firstApply = Task { await controller.apply(CursorPreset.blue.colors) }
    await backend.waitUntilWritePaused()
    #expect(controller.isApplying)
    await controller.apply(CursorPreset.red.colors)
    await controller.refresh()
    let busyCounts = await backend.counts()
    #expect(busyCounts.writes == 1)
    #expect(busyCounts.reads == 1)
    await backend.releaseWrite()
    await firstApply.value
    #expect(controller.colors == CursorPreset.blue.colors)
    #expect(!controller.isApplying)
    #expect(controller.error == nil)
  }

  @MainActor
  @Test
  func testOldRefreshCannotOverwriteCompletedColorWrite() async {
    let backend = CursorColorBackend()
    let controller = makeController(using: backend)
    await controller.refresh()
    await backend.pauseNextRead()
    let oldRefresh = Task { await controller.refresh() }
    await backend.waitUntilReadPaused()
    #expect(controller.isRefreshing)
    await controller.apply(CursorPreset.purple.colors)
    #expect(controller.colors == CursorPreset.purple.colors)
    await backend.releaseRead()
    await oldRefresh.value
    #expect(controller.colors == CursorPreset.purple.colors)
    #expect(controller.error == nil)
    #expect(!controller.isRefreshing)
    #expect(!controller.isApplying)
  }

  @MainActor
  @Test
  func testRepeatedRefreshIsIgnoredWhileReadIsPending() async {
    let backend = CursorColorBackend()
    let controller = makeController(using: backend)
    await backend.pauseNextRead()
    let firstRefresh = Task { await controller.refresh() }
    await backend.waitUntilReadPaused()
    await controller.refresh()
    let counts = await backend.counts()
    #expect(counts.reads == 1)
    await backend.releaseRead()
    await firstRefresh.value
    #expect(controller.available)
    #expect(!controller.isRefreshing)
  }

  @MainActor
  @Test
  func testDefaultResetDisablesCustomization() async {
    let backend = CursorColorBackend(value: CursorPreset.orange.colors)
    let controller = makeController(using: backend)
    await controller.refresh()
    #expect(controller.colors.customized)
    await controller.apply(CursorPreset.standard.colors)
    #expect(controller.colors == .standard)
    #expect(!controller.colors.customized)
    #expect(controller.selectionName == "Default")
    #expect(controller.error == nil)
    let written = await backend.lastWritten
    #expect(written == .standard)
  }

  @MainActor
  private func makeController(using backend: CursorColorBackend) -> CursorColorController {
    CursorColorController(reader: { await backend.read() }, writer: { await backend.write($0) })
  }
}

private actor CursorColorBackend {
  private var value: CursorColors?
  private var appliesWrites = true
  private var unavailableAfterWrite = false
  private var writeOverride: CursorColors?
  private var writerFailure: String?
  private var pauseRead = false
  private var pauseWrite = false
  private var suspendedRead: CheckedContinuation<Void, Never>?
  private var suspendedWrite: CheckedContinuation<Void, Never>?
  private var readWaiters: [CheckedContinuation<Void, Never>] = []
  private var writeWaiters: [CheckedContinuation<Void, Never>] = []
  private var readCount = 0
  private var writeCount = 0
  private(set) var lastWritten: CursorColors?

  init(value: CursorColors? = .standard) { self.value = value }

  func setValue(_ colors: CursorColors?) { value = colors }
  func setAppliesWrites(_ value: Bool) { appliesWrites = value }
  func setUnavailableAfterWrite(_ value: Bool) { unavailableAfterWrite = value }
  func setWriteOverride(_ colors: CursorColors?) { writeOverride = colors }
  func setWriterFailure(_ failure: String?) { writerFailure = failure }
  func counts() -> (reads: Int, writes: Int) { (readCount, writeCount) }
  func pauseNextRead() { pauseRead = true }
  func pauseNextWrite() { pauseWrite = true }

  func waitUntilReadPaused() async {
    if suspendedRead != nil { return }
    await withCheckedContinuation { readWaiters.append($0) }
  }

  func waitUntilWritePaused() async {
    if suspendedWrite != nil { return }
    await withCheckedContinuation { writeWaiters.append($0) }
  }

  func releaseRead() {
    suspendedRead?.resume()
    suspendedRead = nil
  }

  func releaseWrite() {
    suspendedWrite?.resume()
    suspendedWrite = nil
  }

  func read() async -> CursorColors? {
    readCount += 1
    let captured = value
    if pauseRead {
      pauseRead = false
      await withCheckedContinuation { continuation in
        suspendedRead = continuation
        for waiter in readWaiters { waiter.resume() }
        readWaiters.removeAll()
      }
    }
    return captured
  }

  func write(_ requested: CursorColors) async -> String? {
    writeCount += 1
    lastWritten = requested
    if pauseWrite {
      pauseWrite = false
      await withCheckedContinuation { continuation in
        suspendedWrite = continuation
        for waiter in writeWaiters { waiter.resume() }
        writeWaiters.removeAll()
      }
    }
    if let writerFailure { return writerFailure }
    if appliesWrites { value = unavailableAfterWrite ? nil : (writeOverride ?? requested) }
    return nil
  }
}

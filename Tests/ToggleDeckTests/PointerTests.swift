import Foundation
import Testing

@testable import ToggleDeck

@Suite(.serialized)
struct PointerTests {
  @Test
  func validSizeRangeAndNativePrecision() {
    for scale in [1.0, 1.25, 1.5, 2, 3, 4] {
      let value = PointerSettings(scale: scale, shakeToFind: true)
      #expect(value.isValid)
      #expect(value.percentLabel == "\(Int(scale * 100))%")
    }
    for scale in [Double.nan, .infinity, -.infinity, 0.999, 4.001] {
      #expect(!PointerSettings(scale: scale, shakeToFind: false).isValid)
    }
    #expect(PointerSettings.standard.matches(PointerSettings(scale: 1.00009, shakeToFind: true)))
    #expect(!PointerSettings.standard.matches(PointerSettings(scale: 1.00011, shakeToFind: true)))
    #expect(!PointerSettings.standard.matches(PointerSettings(scale: 1, shakeToFind: false)))
  }

  @Test
  func nativePointerChangesVerifyOnlyTheDomainsBeingChanged() {
    let original = PointerSettings(scale: 1.25, shakeToFind: true)
    let shakeOnly = AccessibilitySystemSettings.PointerChanges(
      previous: original, requested: PointerSettings(scale: 1.25, shakeToFind: false))
    #expect(!shakeOnly.scale && shakeOnly.shake)
    let sizeOnly = AccessibilitySystemSettings.PointerChanges(
      previous: original, requested: PointerSettings(scale: 1, shakeToFind: true))
    #expect(sizeOnly.scale && !sizeOnly.shake)
    let both = AccessibilitySystemSettings.PointerChanges(
      previous: original, requested: PointerSettings(scale: 1, shakeToFind: false))
    #expect(both.scale && both.shake)
    let nativePrecision = AccessibilitySystemSettings.PointerChanges(
      previous: original, requested: PointerSettings(scale: 1.25004, shakeToFind: true))
    #expect(!nativePrecision.scale && !nativePrecision.shake)
  }

  @MainActor
  @Test
  func previewInstancesNeverReadOrWriteSystemSettings() async {
    let backend = PointerBackend()
    let first = PointerController(
      preview: true, reader: { await backend.read() }, writer: { await backend.write($0) })
    let second = PointerController.preview(settings: PointerSettings(scale: 3, shakeToFind: false))
    await first.refresh()
    await first.apply(PointerSettings(scale: 2, shakeToFind: false))
    #expect(first.settings == PointerSettings(scale: 2, shakeToFind: false))
    #expect(second.settings == PointerSettings(scale: 3, shakeToFind: false))
    #expect(PointerController.preview().settings == .standard)
    #expect(
      PointerController.preview(settings: PointerSettings(scale: .nan, shakeToFind: false)).settings
        == .standard)
    #expect(first.available && !first.isLoading && !first.isApplying)
    let counts = await backend.counts()
    #expect(counts.reads == 0 && counts.writes == 0)
  }

  @MainActor
  @Test
  func initialAndUnavailableSettingsNeverReachWriter() async {
    let backend = PointerBackend(value: nil)
    let pointer = controller(backend)
    await pointer.apply(PointerSettings(scale: 2, shakeToFind: false))
    #expect(pointer.isLoading && !pointer.available)
    await pointer.refresh()
    #expect(!pointer.isLoading && !pointer.available && pointer.error != nil)
    await pointer.apply(PointerSettings(scale: 2, shakeToFind: false))
    let counts = await backend.counts()
    #expect(counts.reads == 1 && counts.writes == 0)
    await backend.setValue(PointerSettings(scale: 1.5, shakeToFind: false))
    await pointer.refresh()
    #expect(pointer.available && pointer.error == nil)
    #expect(pointer.settings == PointerSettings(scale: 1.5, shakeToFind: false))
  }

  @MainActor
  @Test
  func malformedReadsAndInvalidRequestsAreRejected() async {
    let backend = PointerBackend(value: PointerSettings(scale: .infinity, shakeToFind: true))
    let pointer = controller(backend)
    await pointer.refresh()
    #expect(!pointer.available && pointer.error != nil && pointer.settings == .standard)
    await backend.setValue(.standard)
    await pointer.refresh()
    for scale in [Double.nan, .infinity, -.infinity, 0.5, 4.01] {
      await pointer.apply(PointerSettings(scale: scale, shakeToFind: false))
      #expect(pointer.error?.contains("100% and 400%") == true)
      #expect(pointer.settings == .standard && !pointer.isApplying)
    }
    let counts = await backend.counts()
    #expect(counts.writes == 0)
  }

  @MainActor
  @Test
  func sameSettingsAvoidAnUnnecessaryWrite() async {
    let backend = PointerBackend()
    let pointer = controller(backend)
    await pointer.refresh()
    await pointer.apply(.standard)
    await pointer.apply(PointerSettings(scale: 1.00004, shakeToFind: true))
    let counts = await backend.counts()
    #expect(counts.writes == 0 && counts.reads == 1)
  }

  @MainActor
  @Test
  func readbackConfirmsSizeAndShakeAndPreservesNativePrecision() async {
    let backend = PointerBackend()
    let pointer = controller(backend)
    await pointer.refresh()
    let requested = PointerSettings(scale: 1.7, shakeToFind: false)
    let actual = PointerSettings(scale: Double(Float(1.7)), shakeToFind: false)
    await backend.setWriteOverride(actual)
    await pointer.apply(requested)
    #expect(pointer.settings == actual)
    #expect(pointer.settings != requested)
    #expect(pointer.error == nil && !pointer.isApplying)
    let counts = await backend.counts()
    #expect(counts.reads == 2 && counts.writes == 1)
  }

  @MainActor
  @Test
  func unchangedNativeSettingCannotBeReportedAsSuccess() async {
    let backend = PointerBackend()
    let pointer = controller(backend)
    await pointer.refresh()
    await backend.setAppliesWrites(false)
    await pointer.apply(PointerSettings(scale: 2, shakeToFind: false))
    #expect(pointer.settings == .standard)
    #expect(pointer.error?.contains("did not apply") == true)
    #expect(!pointer.isApplying)
  }

  @MainActor
  @Test
  func shakeReadbackMustMatchEvenWhenSizeWasApplied() async {
    let backend = PointerBackend()
    let pointer = controller(backend)
    await pointer.refresh()
    await backend.setWriteOverride(PointerSettings(scale: 2, shakeToFind: true))
    await pointer.apply(PointerSettings(scale: 2, shakeToFind: false))
    #expect(pointer.settings == PointerSettings(scale: 2, shakeToFind: true))
    #expect(pointer.error != nil && !pointer.isApplying)
  }

  @MainActor
  @Test
  func rejectedWritePreservesStateAndCanBeRetried() async {
    let backend = PointerBackend()
    let pointer = controller(backend)
    await pointer.refresh()
    await backend.setWriterFailure("The native setting could not be saved.")
    await pointer.apply(PointerSettings(scale: 2, shakeToFind: false))
    #expect(pointer.settings == .standard)
    #expect(pointer.error == "The native setting could not be saved.")
    #expect(!pointer.isApplying)
    await pointer.refresh(clearError: false)
    #expect(pointer.error != nil)
    await backend.setWriterFailure(nil)
    await pointer.apply(PointerSettings(scale: 2, shakeToFind: false))
    #expect(pointer.settings == PointerSettings(scale: 2, shakeToFind: false))
    #expect(pointer.error == nil && !pointer.isApplying)
  }

  @MainActor
  @Test
  func failedRollbackShowsActualSettingsAndPreservesFailure() async {
    let backend = PointerBackend()
    let actual = PointerSettings(scale: 1.25, shakeToFind: false)
    let failure = "The previous pointer setting could not be confirmed as restored."
    let pointer = PointerController(
      reader: { await backend.read() },
      writer: { _ in
        await backend.setValue(actual)
        return failure
      })
    await pointer.refresh()
    await pointer.apply(PointerSettings(scale: 2, shakeToFind: true))
    #expect(pointer.settings == actual)
    #expect(pointer.available && !pointer.isApplying)
    #expect(pointer.error == failure)
    let counts = await backend.counts()
    #expect(counts.reads == 2)
    await pointer.refresh(clearError: false)
    #expect(pointer.settings == actual && pointer.error == failure)
  }

  @MainActor
  @Test
  func failedWriteWithUnavailableReadbackBlocksEditsUntilRefresh() async {
    let backend = PointerBackend()
    let failure = "The pointer setting could not be saved."
    let pointer = PointerController(
      reader: { await backend.read() },
      writer: { requested in
        _ = await backend.write(requested)
        await backend.setValue(nil)
        return failure
      })
    await pointer.refresh()
    await pointer.apply(PointerSettings(scale: 2, shakeToFind: false))
    #expect(pointer.settings == .standard)
    #expect(!pointer.available && !pointer.isApplying)
    #expect(pointer.error == failure)
    await pointer.apply(PointerSettings(scale: 3, shakeToFind: false))
    let counts = await backend.counts()
    #expect(counts.reads == 2 && counts.writes == 1)
    await backend.setValue(PointerSettings(scale: 2, shakeToFind: false))
    await pointer.refresh()
    #expect(pointer.settings == PointerSettings(scale: 2, shakeToFind: false))
    #expect(pointer.available && pointer.error == nil)
  }

  @MainActor
  @Test
  func failedWriteWithMalformedReadbackPreservesLastKnownSettings() async {
    let backend = PointerBackend()
    let failure = "The pointer setting could not be saved."
    let pointer = PointerController(
      reader: { await backend.read() },
      writer: { _ in
        await backend.setValue(PointerSettings(scale: .infinity, shakeToFind: false))
        return failure
      })
    await pointer.refresh()
    await pointer.apply(PointerSettings(scale: 2, shakeToFind: false))
    #expect(pointer.settings == .standard)
    #expect(!pointer.available && !pointer.isApplying)
    #expect(pointer.error == failure)
  }

  @MainActor
  @Test
  func unavailableReadbackRequiresRefreshBeforeFurtherWrites() async {
    let backend = PointerBackend()
    let pointer = controller(backend)
    await pointer.refresh()
    await backend.setUnavailableAfterWrite(true)
    await pointer.apply(PointerSettings(scale: 2, shakeToFind: false))
    #expect(pointer.settings == .standard && !pointer.available)
    #expect(pointer.error?.contains("Could not confirm") == true)
    await pointer.apply(PointerSettings(scale: 3, shakeToFind: false))
    let counts = await backend.counts()
    #expect(counts.writes == 1)
    await backend.setValue(.standard)
    await pointer.refresh()
    #expect(pointer.available && pointer.error == nil)
  }

  @MainActor
  @Test
  func automaticRefreshKeepsFailureUntilStateChangesOrUserRefreshes() async {
    let backend = PointerBackend()
    let pointer = controller(backend)
    await pointer.refresh()
    await backend.setWriterFailure("Save failed.")
    await pointer.apply(PointerSettings(scale: 2, shakeToFind: true))
    await pointer.refresh(clearError: false)
    #expect(pointer.error == "Save failed.")
    await backend.setValue(PointerSettings(scale: 3, shakeToFind: true))
    await pointer.refresh(clearError: false)
    #expect(pointer.settings.scale == 3 && pointer.error == nil)
    await pointer.apply(PointerSettings(scale: 2, shakeToFind: true))
    #expect(pointer.error == "Save failed.")
    await pointer.refresh()
    #expect(pointer.error == nil)
  }

  @MainActor
  @Test
  func pendingWriteBlocksAnotherWriteAndRefresh() async {
    let backend = PointerBackend()
    let pointer = controller(backend)
    await pointer.refresh()
    await backend.pauseNextWrite()
    let applying = Task { await pointer.apply(PointerSettings(scale: 2, shakeToFind: false)) }
    await backend.waitUntilWritePaused()
    #expect(pointer.isApplying)
    await pointer.apply(PointerSettings(scale: 4, shakeToFind: true))
    await pointer.refresh()
    let counts = await backend.counts()
    #expect(counts.reads == 1 && counts.writes == 1)
    await backend.releaseWrite()
    await applying.value
    #expect(pointer.settings == PointerSettings(scale: 2, shakeToFind: false))
    #expect(!pointer.isApplying && pointer.error == nil)
  }

  @MainActor
  @Test
  func staleRefreshCannotOverwriteVerifiedWrite() async {
    let backend = PointerBackend()
    let pointer = controller(backend)
    await pointer.refresh()
    await backend.pauseNextRead()
    let reading = Task { await pointer.refresh() }
    await backend.waitUntilReadPaused()
    #expect(pointer.isRefreshing)
    await pointer.refresh()
    await pointer.apply(PointerSettings(scale: 3, shakeToFind: false))
    await backend.releaseRead()
    await reading.value
    #expect(pointer.settings == PointerSettings(scale: 3, shakeToFind: false))
    #expect(!pointer.isRefreshing && !pointer.isApplying && pointer.error == nil)
    let counts = await backend.counts()
    #expect(counts.reads == 3 && counts.writes == 1)
  }

  @MainActor
  private func controller(_ backend: PointerBackend) -> PointerController {
    PointerController(reader: { await backend.read() }, writer: { await backend.write($0) })
  }
}

private actor PointerBackend {
  private var value: PointerSettings?
  private var appliesWrites = true
  private var unavailableAfterWrite = false
  private var writeOverride: PointerSettings?
  private var writerFailure: String?
  private var pauseRead = false
  private var pauseWrite = false
  private var suspendedRead: CheckedContinuation<Void, Never>?
  private var suspendedWrite: CheckedContinuation<Void, Never>?
  private var readWaiters: [CheckedContinuation<Void, Never>] = []
  private var writeWaiters: [CheckedContinuation<Void, Never>] = []
  private var readCount = 0
  private var writeCount = 0

  init(value: PointerSettings? = .standard) { self.value = value }
  func setValue(_ value: PointerSettings?) { self.value = value }
  func setAppliesWrites(_ value: Bool) { appliesWrites = value }
  func setUnavailableAfterWrite(_ value: Bool) { unavailableAfterWrite = value }
  func setWriteOverride(_ value: PointerSettings?) { writeOverride = value }
  func setWriterFailure(_ value: String?) { writerFailure = value }
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

  func read() async -> PointerSettings? {
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

  func write(_ requested: PointerSettings) async -> String? {
    writeCount += 1
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

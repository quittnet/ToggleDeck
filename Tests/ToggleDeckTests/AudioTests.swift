import Foundation
import Testing

@testable import ToggleDeck

@Suite(.serialized)
struct AudioTests {
  @Test
  func snapshotsRejectAmbiguousDevicesAndInvalidVolume() {
    #expect(AudioSnapshot.sample.isValid)
    #expect(AudioSnapshot.empty.isValid)
    var value = AudioSnapshot.sample
    value.outputs.append(value.outputs[0])
    #expect(!value.isValid)
    value = .sample
    value.selectedUID = "disconnected"
    #expect(!value.isValid)
    for volume in [Double.nan, .infinity, -.infinity, -0.01, 1.01] {
      value = .sample
      value.volume = volume
      #expect(!value.isValid)
    }
    value = .sample
    value.volume = nil
    #expect(!value.isValid)
    value.canSetVolume = false
    #expect(value.isValid)
  }

  @MainActor
  @Test
  func initializationAndRefreshNeverWriteAudioSettings() async {
    let backend = FakeAudioBackend()
    let audio = controller(backend)
    #expect(audio.isLoading)
    #expect(!audio.available)
    let initial = await backend.counts()
    #expect(initial.reads == 0 && initial.outputs == 0 && initial.volumes == 0)
    await audio.selectOutput("preview-headphones")
    await audio.setVolume(0.8)
    await audio.refresh()
    #expect(audio.snapshot == .sample)
    #expect(audio.available && !audio.isLoading && !audio.isRefreshing)
    let refreshed = await backend.counts()
    #expect(refreshed.reads == 1 && refreshed.outputs == 0 && refreshed.volumes == 0)
  }

  @MainActor
  @Test
  func previewsAreMemoryOnlyIndependentAndKeepMuteOn() async {
    let backend = FakeAudioBackend()
    let audio = AudioController(
      preview: true, reader: { await backend.read() },
      outputWriter: { await backend.select($0) }, volumeWriter: { await backend.volume($0, $1) })
    var muted = AudioSnapshot.sample
    muted.isMuted = true
    let second = AudioController.preview(snapshot: muted)
    await audio.refresh()
    await audio.selectOutput("preview-headphones")
    await audio.setVolume(0.8)
    await second.setVolume(0.25)
    #expect(audio.selectedName == "Headphones")
    #expect(audio.volume == 0.8)
    #expect(second.selectedName == "Mac Speakers")
    #expect(second.volume == 0.25)
    #expect(second.isMuted == true)
    #expect(second.summary == "Mac Speakers · Muted")
    #expect(AudioController.preview().snapshot == .sample)
    let counts = await backend.counts()
    #expect(counts.reads == 0 && counts.outputs == 0 && counts.volumes == 0)
  }

  @MainActor
  @Test
  func selectedDeviceMustBeConfirmedByReadback() async {
    let backend = FakeAudioBackend()
    let audio = controller(backend)
    await audio.refresh()
    await backend.setAppliesSelection(false)
    await audio.selectOutput("preview-headphones")
    #expect(audio.selectedName == "Mac Speakers")
    #expect(audio.error?.contains("did not switch") == true)
    #expect(!audio.isApplying)
    await backend.setAppliesSelection(true)
    await audio.selectOutput("preview-headphones")
    #expect(audio.selectedName == "Headphones")
    #expect(audio.error == nil)
    let requests = await backend.selectedRequests
    #expect(requests == ["preview-headphones", "preview-headphones"])
  }

  @MainActor
  @Test
  func disconnectedOutputUpdatesListWithoutSelectingAnotherDevice() async {
    let backend = FakeAudioBackend()
    let audio = controller(backend)
    await audio.refresh()
    var disconnected = AudioSnapshot.sample
    disconnected.outputs.removeAll { $0.uid == "preview-headphones" }
    await backend.setSnapshot(disconnected)
    await audio.selectOutput("preview-headphones")
    #expect(audio.outputs.count == 1)
    #expect(audio.selectedName == "Mac Speakers")
    #expect(audio.error == "Output disconnected.")
    #expect(!audio.isApplying)
    await audio.selectOutput("absent-device")
    #expect(audio.error?.contains("no longer connected") == true)
    let counts = await backend.counts()
    #expect(counts.outputs == 1)
  }

  @MainActor
  @Test
  func readOnlyDeviceAndInvalidVolumesNeverReachWriter() async {
    var readOnly = AudioSnapshot.sample
    readOnly.canSetVolume = false
    let backend = FakeAudioBackend(snapshot: readOnly)
    let audio = controller(backend)
    await audio.refresh()
    await audio.setVolume(0.9)
    #expect(audio.error == "Adjust volume on this device.")
    #expect(audio.volume == 0.55)
    for value in [Double.nan, .infinity, -.infinity, -0.1, 1.1] {
      await audio.setVolume(value)
      #expect(audio.error == "Choose a volume between 0 and 100 percent.")
    }
    let counts = await backend.counts()
    #expect(counts.volumes == 0)
  }

  @MainActor
  @Test
  func volumeWritesTargetCurrentUIDPreserveMuteAndAcceptHardwareSteps() async {
    var muted = AudioSnapshot.sample
    muted.isMuted = true
    let backend = FakeAudioBackend(snapshot: muted)
    let audio = controller(backend)
    await audio.refresh()
    await backend.setVolumeOverride(0.61)
    await audio.setVolume(0.6)
    #expect(audio.volume == 0.61)
    #expect(audio.isMuted == true)
    #expect(audio.error == nil)
    let requests = await backend.volumeRequests
    #expect(requests.count == 1)
    #expect(requests.first?.0 == "preview-speakers")
    #expect(requests.first?.1 == 0.6)
    await backend.setVolumeOverride(0.2)
    await audio.setVolume(0.8)
    #expect(audio.volume == 0.2)
    #expect(audio.isMuted == true)
    #expect(audio.error?.contains("did not apply") == true)
  }

  @MainActor
  @Test
  func unavailableReadbackBlocksFurtherChangesUntilRefreshRecovers() async {
    let backend = FakeAudioBackend()
    let audio = controller(backend)
    await audio.refresh()
    await backend.setUnavailableAfterWrite(true)
    await audio.selectOutput("preview-headphones")
    #expect(!audio.available)
    #expect(audio.selectedName == "Mac Speakers")
    #expect(audio.error?.contains("Could not confirm") == true)
    await audio.setVolume(0.9)
    let failed = await backend.counts()
    #expect(failed.outputs == 1 && failed.volumes == 0)
    await backend.setSnapshot(.sample)
    await backend.setUnavailableAfterWrite(false)
    await audio.refresh()
    #expect(audio.available)
    #expect(audio.error == nil)
  }

  @MainActor
  @Test
  func refreshFailuresAndEmptyDevicesHaveRecoveryStates() async {
    let backend = FakeAudioBackend(snapshot: nil)
    let audio = controller(backend)
    await audio.refresh()
    #expect(!audio.isLoading && !audio.available)
    #expect(audio.error?.contains("could not be read") == true)
    await backend.setSnapshot(.empty)
    await audio.refresh()
    #expect(!audio.available)
    #expect(audio.error?.contains("No audio output") == true)
    await backend.setSnapshot(.sample)
    await audio.refresh()
    #expect(audio.available && audio.error == nil)
  }

  @MainActor
  @Test
  func oldRefreshCannotOverwriteCompletedOutputSelection() async {
    let backend = FakeAudioBackend()
    let audio = controller(backend)
    await audio.refresh()
    await backend.pauseNextRead()
    let oldRefresh = Task { await audio.refresh() }
    await backend.waitUntilReadPaused()
    await audio.selectOutput("preview-headphones")
    #expect(audio.selectedName == "Headphones")
    await backend.releaseRead()
    await oldRefresh.value
    #expect(audio.selectedName == "Headphones")
    #expect(audio.error == nil && !audio.isRefreshing)
  }

  @MainActor
  @Test
  func oldRefreshCannotOverwriteCompletedVolumeChange() async {
    let backend = FakeAudioBackend()
    let audio = controller(backend)
    await audio.refresh()
    await backend.pauseNextRead()
    let oldRefresh = Task { await audio.refresh() }
    await backend.waitUntilReadPaused()
    await audio.setVolume(0.85)
    await backend.releaseRead()
    await oldRefresh.value
    #expect(audio.volume == 0.85)
    #expect(audio.error == nil && !audio.isRefreshing)
  }

  @MainActor
  @Test
  func concurrentWritesAreIgnoredAndOutputChangeDuringVolumeWriteIsReported() async {
    let backend = FakeAudioBackend()
    let audio = controller(backend)
    await audio.refresh()
    await backend.pauseNextWrite()
    let change = Task { await audio.setVolume(0.75) }
    await backend.waitUntilWritePaused()
    #expect(audio.isApplying)
    await audio.setVolume(0.2)
    await audio.selectOutput("preview-headphones")
    var moved = AudioSnapshot.sample
    moved.selectedUID = "preview-headphones"
    await backend.setSnapshot(moved)
    await backend.releaseWrite()
    await change.value
    #expect(audio.selectedName == "Headphones")
    #expect(audio.error == "Output changed.")
    #expect(!audio.isApplying)
    let counts = await backend.counts()
    #expect(counts.volumes == 1 && counts.outputs == 0)
  }

  @MainActor
  @Test
  func automaticRefreshPreservesWriteFailureUntilExplicitRetryOrExternalChange() async {
    let backend = FakeAudioBackend()
    let audio = controller(backend)
    await audio.refresh()
    await backend.setVolumeFailure("Device rejected volume.")
    await audio.setVolume(0.8)
    #expect(audio.error == "Device rejected volume.")
    await audio.refresh(clearError: false)
    #expect(audio.error == "Device rejected volume.")
    await backend.setVolumeFailure(nil)
    await audio.setVolume(0.8)
    #expect(audio.volume == 0.8 && audio.error == nil)
    await backend.setVolumeFailure("Device rejected volume.")
    await audio.setVolume(0.4)
    var externallyChanged = AudioSnapshot.sample
    externallyChanged.volume = 0.9
    await backend.setSnapshot(externallyChanged)
    await audio.refresh(clearError: false)
    #expect(audio.volume == 0.9 && audio.error == nil)
  }

  @MainActor
  @Test
  func readOnlyOutputSelectionNeverReachesWriter() async {
    var readOnly = AudioSnapshot.sample
    readOnly.canSelectOutput = false
    let backend = FakeAudioBackend(snapshot: readOnly)
    let audio = controller(backend)
    await audio.refresh()
    await audio.selectOutput("preview-headphones")
    #expect(audio.error?.contains("cannot change") == true)
    let counts = await backend.counts()
    #expect(counts.outputs == 0 && counts.volumes == 0)
  }

  @MainActor
  private func controller(_ backend: FakeAudioBackend) -> AudioController {
    AudioController(
      reader: { await backend.read() }, outputWriter: { await backend.select($0) },
      volumeWriter: { await backend.volume($0, $1) })
  }
}

private actor FakeAudioBackend {
  private var snapshot: AudioSnapshot?
  private var appliesSelection = true
  private var unavailableAfterWrite = false
  private var volumeOverride: Double?
  private var volumeFailure: String?
  private var pauseRead = false
  private var pauseWrite = false
  private var suspendedRead: CheckedContinuation<Void, Never>?
  private var suspendedWrite: CheckedContinuation<Void, Never>?
  private var readWaiters: [CheckedContinuation<Void, Never>] = []
  private var writeWaiters: [CheckedContinuation<Void, Never>] = []
  private var reads = 0
  private(set) var selectedRequests: [String] = []
  private(set) var volumeRequests: [(String, Double)] = []

  init(snapshot: AudioSnapshot? = .sample) { self.snapshot = snapshot }
  func setSnapshot(_ value: AudioSnapshot?) { snapshot = value }
  func setAppliesSelection(_ value: Bool) { appliesSelection = value }
  func setUnavailableAfterWrite(_ value: Bool) { unavailableAfterWrite = value }
  func setVolumeOverride(_ value: Double?) { volumeOverride = value }
  func setVolumeFailure(_ value: String?) { volumeFailure = value }
  func pauseNextRead() { pauseRead = true }
  func pauseNextWrite() { pauseWrite = true }
  func counts() -> (reads: Int, outputs: Int, volumes: Int) {
    (reads, selectedRequests.count, volumeRequests.count)
  }

  func read() async -> AudioSnapshot? {
    reads += 1
    let captured = snapshot
    if pauseRead {
      pauseRead = false
      await withCheckedContinuation { continuation in
        suspendedRead = continuation
        for waiter in readWaiters { waiter.resume() }
        readWaiters = []
      }
    }
    return captured
  }

  func select(_ uid: String) async -> String? {
    selectedRequests.append(uid)
    await waitForWrite()
    guard var current = snapshot, current.outputs.contains(where: { $0.uid == uid }) else {
      return "Output disconnected."
    }
    if appliesSelection { current.selectedUID = uid }
    snapshot = unavailableAfterWrite ? nil : current
    return nil
  }

  func volume(_ uid: String, _ value: Double) async -> String? {
    volumeRequests.append((uid, value))
    await waitForWrite()
    guard var current = snapshot, current.selectedUID == uid else { return "Output changed." }
    if let volumeFailure { return volumeFailure }
    current.volume = volumeOverride ?? value
    snapshot = unavailableAfterWrite ? nil : current
    return nil
  }

  private func waitForWrite() async {
    if pauseWrite {
      pauseWrite = false
      await withCheckedContinuation { continuation in
        suspendedWrite = continuation
        for waiter in writeWaiters { waiter.resume() }
        writeWaiters = []
      }
    }
  }

  func waitUntilReadPaused() async {
    if suspendedRead == nil { await withCheckedContinuation { readWaiters.append($0) } }
  }

  func waitUntilWritePaused() async {
    if suspendedWrite == nil { await withCheckedContinuation { writeWaiters.append($0) } }
  }

  func releaseRead() {
    suspendedRead?.resume()
    suspendedRead = nil
  }
  func releaseWrite() {
    suspendedWrite?.resume()
    suspendedWrite = nil
  }
}

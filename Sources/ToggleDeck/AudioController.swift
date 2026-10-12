import Combine
import Foundation

@MainActor
final class AudioController: ObservableObject {
  static let shared = AudioController()

  @Published private(set) var snapshot = AudioSnapshot.empty
  @Published private(set) var isLoading = true
  @Published private(set) var isRefreshing = false
  @Published private(set) var isApplying = false
  @Published private(set) var available = false
  @Published private(set) var error: String?

  typealias Reader = @Sendable () async -> AudioSnapshot?
  typealias OutputWriter = @Sendable (String) async -> String?
  typealias VolumeWriter = @Sendable (String, Double) async -> String?
  private let reader: Reader
  private let outputWriter: OutputWriter
  private let volumeWriter: VolumeWriter
  private let isPreview: Bool
  private var revision: UInt64 = 0
  private var observation: AudioSystemObservation?
  private var queuedRefresh = false
  private var queuedClearError = false

  init(
    preview: Bool = false, reader: Reader? = nil, outputWriter: OutputWriter? = nil,
    volumeWriter: VolumeWriter? = nil
  ) {
    isPreview = preview
    self.reader = reader ?? { await Task.detached { AudioSystem.read() }.value }
    self.outputWriter =
      outputWriter ?? { uid in
        await Task.detached { AudioSystem.selectOutput(uid) }.value
      }
    self.volumeWriter =
      volumeWriter ?? { uid, value in
        await Task.detached { AudioSystem.setVolume(uid, value: value) }.value
      }
    if preview {
      snapshot = .sample
      isLoading = false
      available = true
    } else if reader == nil && outputWriter == nil && volumeWriter == nil {
      observation = AudioSystemObservation { [weak self] in
        Task { @MainActor in await self?.refresh(clearError: false) }
      }
    }
  }

  static func preview(snapshot: AudioSnapshot = .sample) -> AudioController {
    let controller = AudioController(preview: true)
    controller.snapshot = snapshot
    controller.available = snapshot.isValid && !snapshot.outputs.isEmpty
    return controller
  }

  var outputs: [AudioOutput] { snapshot.outputs }
  var selectedName: String { snapshot.selected?.name ?? "No Output" }
  var volume: Double? { snapshot.volume }
  var canSetVolume: Bool { available && snapshot.canSetVolume }
  var isMuted: Bool? { snapshot.isMuted }
  var summary: String {
    if isLoading { return "Reading…" }
    if isApplying { return "Applying…" }
    if !available { return "Unavailable" }
    if isMuted == true { return "\(selectedName) · Muted" }
    if let volume { return "\(selectedName) · \(Int((volume * 100).rounded()))%" }
    return selectedName
  }

  func refresh(clearError: Bool = true) async {
    guard !isPreview else { return }
    if isApplying || isRefreshing {
      queuedRefresh = true
      queuedClearError = queuedClearError || clearError
      return
    }
    isRefreshing = true
    let started = revision
    defer {
      isRefreshing = false
      runQueuedRefresh()
    }
    let value = await reader()
    guard started == revision, !isApplying else { return }
    isLoading = false
    guard let value, value.isValid else {
      available = false
      error = "Sound settings could not be read. Refresh or open Sound Settings."
      return
    }
    let changed = snapshot != value
    accept(value)
    if value.outputs.isEmpty {
      error = "No audio output is connected. Connect a device, then refresh."
    } else if clearError || changed {
      error = nil
    }
  }

  func selectOutput(_ uid: String) async {
    guard !isLoading, !isApplying, available else { return }
    guard snapshot.canSelectOutput else {
      error = "macOS cannot change the output here. Open Sound Settings."
      return
    }
    guard outputs.contains(where: { $0.uid == uid }) else {
      error = "That output is no longer connected. Refresh and choose another device."
      return
    }
    guard uid != snapshot.selectedUID else {
      error = nil
      return
    }
    revision += 1
    if isPreview {
      snapshot.selectedUID = uid
      error = nil
      return
    }
    isApplying = true
    error = nil
    defer { finishApply() }
    let failure = await outputWriter(uid)
    guard let actual = await readBack(failure: failure) else { return }
    if let failure {
      error = failure
      return
    }
    guard actual.selectedUID == uid else {
      error = "macOS did not switch to that output. Refresh or open Sound Settings."
      return
    }
    error = nil
  }

  func setVolume(_ value: Double) async {
    guard value.isFinite, (0...1).contains(value) else {
      error = "Choose a volume between 0 and 100 percent."
      return
    }
    guard !isLoading, !isApplying, available else { return }
    guard canSetVolume, let uid = snapshot.selectedUID, let current = volume else {
      error = "Adjust volume on this device."
      return
    }
    guard abs(current - value) > 0.0001 else {
      error = nil
      return
    }
    revision += 1
    if isPreview {
      snapshot.volume = value
      error = nil
      return
    }
    isApplying = true
    error = nil
    defer { finishApply() }
    let failure = await volumeWriter(uid, value)
    guard let actual = await readBack(failure: failure) else { return }
    if let failure {
      error = failure
      return
    }
    guard actual.selectedUID == uid else {
      error = "The output changed before the volume was confirmed. Try again on the current device."
      return
    }
    // HAL scalar volume is quantized to the nearest hardware-supported step.
    guard let actualVolume = actual.volume, abs(actualVolume - value) <= 0.04 else {
      error = "macOS did not apply that volume. Refresh or adjust it on this device."
      return
    }
    error = nil
  }

  private func readBack(failure: String?) async -> AudioSnapshot? {
    guard let actual = await reader(), actual.isValid else {
      available = false
      error = failure ?? "Could not confirm the sound change. Refresh or open Sound Settings."
      return nil
    }
    accept(actual)
    return actual
  }

  private func accept(_ value: AudioSnapshot) {
    snapshot = value
    available = !value.outputs.isEmpty
    observation?.observeDevice(value.selected?.deviceID)
  }

  private func finishApply() {
    isApplying = false
    runQueuedRefresh()
  }

  private func runQueuedRefresh() {
    guard queuedRefresh, !isApplying, !isRefreshing else { return }
    let clearError = queuedClearError
    queuedRefresh = false
    queuedClearError = false
    Task { @MainActor [weak self] in await self?.refresh(clearError: clearError) }
  }
}

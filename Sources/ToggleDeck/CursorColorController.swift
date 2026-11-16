import Combine
import Foundation

@MainActor
final class CursorColorController: ObservableObject {
  static let shared = CursorColorController()

  @Published private(set) var colors = CursorColors.standard
  @Published private(set) var isLoading = true
  @Published private(set) var isRefreshing = false
  @Published private(set) var isApplying = false
  @Published private(set) var available = false
  @Published private(set) var error: String?

  typealias Reader = @Sendable () async -> CursorColors?
  typealias Writer = @Sendable (CursorColors) async -> String?
  private let reader: Reader
  private let writer: Writer
  private let isPreview: Bool
  private var revision: UInt64 = 0
  private var queuedRefresh = false
  private var queuedClearError = false
  private var colorObservation: AnyCancellable?
  private var paletteObservation: AnyCancellable?
  let palettes: CursorPaletteStore

  init(
    preview: Bool = false, reader: Reader? = nil, writer: Writer? = nil,
    palettes: CursorPaletteStore? = nil
  ) {
    isPreview = preview
    self.palettes = palettes ?? (preview || reader != nil || writer != nil ? .preview() : .shared)
    self.reader = reader ?? { await Task.detached { CursorSystemColors.read() }.value }
    self.writer =
      writer ?? { colors in
        await Task.detached { CursorSystemColors.write(colors) }.value
      }
    paletteObservation = self.palettes.objectWillChange.sink { [weak self] _ in
      self?.objectWillChange.send()
    }
    if preview {
      isLoading = false
      available = true
    } else if reader == nil {
      colorObservation = DistributedNotificationCenter.default()
        .publisher(for: Notification.Name("AXInterfaceCursorStatusDidChangeNotification"))
        .sink { [weak self] _ in
          Task { @MainActor in await self?.refresh(clearError: false) }
        }
    }
  }

  static func preview(colors: CursorColors = .standard) -> CursorColorController {
    let controller = CursorColorController(preview: true)
    controller.colors = colors
    return controller
  }

  var selectionName: String {
    palettes.matching(colors)?.name ?? CursorPreset.matching(colors)?.rawValue ?? "Custom"
  }

  func refresh(clearError: Bool = true) async {
    guard !isPreview else { return }
    // A change notification during a read or write must not be lost: the
    // in-flight read may predate it. Replay once when the operation ends.
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
      error = "macOS pointer colors could not be read. Refresh or open Pointer Settings."
      return
    }
    let changed = !colors.matches(value) || colors.customized != value.customized
    colors = value
    rememberCustom(value)
    available = true
    if clearError || changed { error = nil }
  }

  func apply(_ requested: CursorColors) async {
    guard !isLoading, !isApplying, available else { return }
    guard requested.isValid else {
      error = "Choose a valid fill and outline color."
      return
    }
    revision += 1
    if isPreview {
      colors = requested
      rememberCustom(requested)
      error = nil
      return
    }
    isApplying = true
    error = nil
    defer {
      isApplying = false
      runQueuedRefresh()
    }
    if let failure = await writer(requested) {
      // The native setter can change WindowServer before persistence fails and
      // the rollback is not guaranteed, so never assume the old colors.
      if let actual = await reader(), actual.isValid {
        colors = actual
        available = true
      } else {
        available = false
      }
      error = failure
      return
    }
    guard let actual = await reader(), actual.isValid else {
      error = "Could not confirm the pointer colors. Refresh or open Pointer Settings."
      return
    }
    colors = actual
    guard actual.matches(requested), actual.customized == requested.customized else {
      error = "macOS did not apply those pointer colors. Try again or open Pointer Settings."
      return
    }
    rememberCustom(actual)
    error = nil
  }

  private func rememberCustom(_ colors: CursorColors) {
    guard colors.customized, CursorPreset.matching(colors) == nil,
      palettes.matching(colors) == nil
    else { return }
    palettes.save(colors)
  }

  private func runQueuedRefresh() {
    guard queuedRefresh, !isApplying, !isRefreshing else { return }
    let clearError = queuedClearError
    queuedRefresh = false
    queuedClearError = false
    Task { @MainActor [weak self] in await self?.refresh(clearError: clearError) }
  }
}

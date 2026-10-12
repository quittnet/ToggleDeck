import Combine
import Foundation

@MainActor
final class PointerController: ObservableObject {
  static let shared = PointerController()

  @Published private(set) var settings = PointerSettings.standard
  @Published private(set) var isLoading = true
  @Published private(set) var isRefreshing = false
  @Published private(set) var isApplying = false
  @Published private(set) var available = false
  @Published private(set) var error: String?

  typealias Reader = @Sendable () async -> PointerSettings?
  typealias Writer = @Sendable (PointerSettings) async -> String?
  private let reader: Reader
  private let writer: Writer
  private let isPreview: Bool
  private var revision: UInt64 = 0
  private var observation: AnyCancellable?

  init(preview: Bool = false, reader: Reader? = nil, writer: Writer? = nil) {
    isPreview = preview
    self.reader =
      reader ?? { await Task.detached { AccessibilitySystemSettings.readPointer() }.value }
    self.writer =
      writer ?? { settings in
        await Task.detached { AccessibilitySystemSettings.writePointer(settings) }.value
      }
    if preview {
      isLoading = false
      available = true
    } else if reader == nil {
      observation = DistributedNotificationCenter.default()
        .publisher(for: Notification.Name("AXInterfaceCursorStatusDidChangeNotification"))
        .sink { [weak self] _ in Task { @MainActor in await self?.refresh(clearError: false) } }
    }
  }

  static func preview(settings: PointerSettings = .standard) -> PointerController {
    let controller = PointerController(preview: true)
    controller.settings = settings.isValid ? settings : .standard
    return controller
  }

  func refresh(clearError: Bool = true) async {
    guard !isPreview, !isRefreshing, !isApplying else { return }
    isRefreshing = true
    let started = revision
    defer { isRefreshing = false }
    let value = await reader()
    guard started == revision, !isApplying else { return }
    isLoading = false
    guard let value, value.isValid else {
      available = false
      error = "Pointer settings could not be read. Refresh or open Pointer Settings."
      return
    }
    let changed = !settings.matches(value)
    settings = value
    available = true
    if clearError || changed { error = nil }
  }

  func apply(_ requested: PointerSettings) async {
    guard !Task.isCancelled, !isLoading, !isApplying, available else { return }
    guard requested.isValid else {
      error = "Choose a pointer size between 100% and 400%."
      return
    }
    guard !settings.matches(requested) else { return }
    revision += 1
    if isPreview {
      settings = requested
      error = nil
      return
    }
    isApplying = true
    error = nil
    defer { isApplying = false }
    if let failure = await writer(requested) {
      // A native setter can change WindowServer before persistence fails.
      // A failed rollback must never leave the UI showing an assumed state.
      if let actual = await reader(), actual.isValid {
        settings = actual
        available = true
      } else {
        available = false
      }
      error = failure
      return
    }
    guard let actual = await reader(), actual.isValid else {
      available = false
      error = "Could not confirm the pointer settings. Refresh or open Pointer Settings."
      return
    }
    settings = actual
    guard actual.matches(requested) else {
      error = "macOS did not apply those pointer settings. Refresh or open Pointer Settings."
      return
    }
    error = nil
  }
}

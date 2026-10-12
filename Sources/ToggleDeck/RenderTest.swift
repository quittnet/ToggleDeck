import AppKit
import SwiftUI

/// Renders the dropdown and the settings window into PNGs without needing a
/// click, a menu bar, or Screen Recording permission. Used to check layout
/// after a UI change: `ToggleDeck --render /tmp/deck`.
@MainActor
enum RenderTest {

  static func run(prefix: String) {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.appearance = NSAppearance(named: .aqua)

    let settingsModel = AppSettings.preview()
    let engine = ToggleEngine.preview()
    let cursor = CursorColorController.preview()
    let pointer = PointerController.preview()
    let audio = AudioController.preview()
    let shortcut = GlobalShortcutController.preview()

    // Real windows, parked offscreen, so SwiftUI's .task and .searchable
    // behave as they do in the shipping app.
    // The dropdown sizes itself, so its window follows the fitting size
    // rather than a hardcoded frame.
    let dropdown = makeSelfSizingWindow(
      NSHostingView(
        rootView: DropdownView(
          engine: engine, settings: settingsModel, cursor: cursor, pointer: pointer, audio: audio,
          onOpenSettings: {}, onQuit: {},
          previewSpecs: Catalog.defaultPinned.compactMap { Catalog.byID[$0] })))
    // Same view fed the whole catalog, to exercise the column wrap.
    let wide = makeSelfSizingWindow(
      NSHostingView(
        rootView: DropdownView(
          engine: engine, settings: settingsModel, cursor: cursor, pointer: pointer, audio: audio,
          onOpenSettings: {}, onQuit: {},
          previewSpecs: Catalog.all)))
    let settings = makeWindow(
      size: NSSize(width: 960, height: 660),
      view: NSHostingView(
        rootView: SettingsView(
          engine: engine, settings: settingsModel, cursor: cursor,
          pointer: pointer, audio: audio, shortcut: shortcut
        ).environment(
          \.colorScheme, .light)))
    let allSettings = makeWindow(
      size: NSSize(width: 960, height: 660),
      view: NSHostingView(
        rootView: SettingsView(
          initialSection: .all, engine: engine, settings: settingsModel, cursor: cursor,
          pointer: pointer, audio: audio, shortcut: shortcut
        )
        .environment(\.colorScheme, .light)))
    let general = makeWindow(
      size: NSSize(width: 960, height: 660),
      view: NSHostingView(
        rootView: SettingsView(
          initialSection: .general, engine: engine, settings: settingsModel, cursor: cursor,
          pointer: pointer, audio: audio, shortcut: shortcut
        )
        .environment(\.colorScheme, .light)))

    // Let the first refresh land so fittingSize is meaningful, then settle
    // the content at its final size. The resize happens before the long
    // settle, not after: SwiftUI re-renders text into a resized offscreen
    // backing store lazily, and capturing right after a resize yields a
    // frame with the switches drawn but the labels missing.
    settle(seconds: 3)
    // Only the single-column dropdown is re-sized. Resizing the full-width
    // window is what drops its text from the capture, and its initial
    // fitting size is already correct, so it is left alone.
    if let view = dropdown.contentView {
      view.layoutSubtreeIfNeeded()
      let fit = view.fittingSize
      if fit.height > 1, fit.width > 1, abs(fit.height - view.bounds.height) > 2 {
        dropdown.setContentSize(fit)
        view.needsDisplay = true
      }
    }
    settle(seconds: 3)

    capture(dropdown, to: "\(prefix)-dropdown.png")
    capture(wide, to: "\(prefix)-dropdown-wide.png")
    capture(settings, to: "\(prefix)-settings.png")
    capture(allSettings, to: "\(prefix)-all.png")
    capture(general, to: "\(prefix)-general.png")

    print("wrote 5 PNGs under \(prefix)-")
  }

  private static func settle(seconds: TimeInterval) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
      RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
  }

  /// Mirrors how NSPopover sizes its content view controller. The window is
  /// resized again after layout settles; this is only a starting frame.
  private static func makeSelfSizingWindow(_ view: NSView) -> NSWindow {
    let fitting = view.fittingSize
    let size = NSSize(width: max(fitting.width, 200), height: max(fitting.height, 120))
    return makeWindow(size: size, view: view)
  }

  private static func makeWindow(size: NSSize, view: NSView) -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.titled, .resizable],
      backing: .buffered, defer: false)
    // Pin the appearance: an offscreen window inherits no effective
    // appearance, which resolves selection materials to flat black.
    window.appearance = NSAppearance(named: .aqua)
    window.contentView = view
    view.appearance = NSAppearance(named: .aqua)
    window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
    window.makeKeyAndOrderFront(nil)
    window.displayIfNeeded()
    return window
  }

  /// Known limit: on a window as wide as the all-196 case (~1800pt), text
  /// drops out of the capture and only the AppKit switches survive — SwiftUI
  /// renders labels into CALayers that `cacheDisplay` does not traverse at
  /// that size. The frame is still usable for checking column structure and
  /// row placement, which is what the wide render is for. `dataWithPDF` was
  /// tried as an alternative and is worse: it loses everything but the search
  /// placeholder. Windows up to the settings panes' size capture in full.
  private static func capture(_ window: NSWindow, to path: String) {
    guard let content = window.contentView else { return }
    content.layoutSubtreeIfNeeded()
    // display(), not displayIfNeeded(): a resize drops the backing store,
    // and a conditional redraw then captures empty text layers.
    content.display()
    guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
    content.cacheDisplay(in: content.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
  }
}

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
    func dropdownWindow(_ specs: [ToggleSpec], dark: Bool = false) -> NSWindow {
      makeSelfSizingWindow(
        NSHostingView(
          rootView: DropdownView(
            engine: engine, settings: settingsModel, cursor: cursor, pointer: pointer,
            audio: audio, onOpenSettings: {}, onQuit: {}, previewSpecs: specs
          )
          // The live popover supplies a material; a captured view has none.
          .background(DeckStyle.panelFallback)
          .environment(\.colorScheme, dark ? .dark : .light)), dark: dark)
    }
    func pane(_ section: SettingsSection, dark: Bool = false) -> NSWindow {
      // The shipping window, so the capture shows its title bar inset.
      makeWindow(
        size: SettingsWindow.defaultSize,
        view: NSHostingView(
          rootView: SettingsView(
            initialSection: section, engine: engine, settings: settingsModel, cursor: cursor,
            pointer: pointer, audio: audio, shortcut: shortcut
          ).environment(\.colorScheme, dark ? .dark : .light)), dark: dark,
        window: SettingsWindow.make(title: "ToggleDeck Settings"))
    }

    let pinned = Catalog.defaultPinned.compactMap { Catalog.byID[$0] }
    let dropdowns = [
      ("dropdown", dropdownWindow(pinned)),
      ("dropdown-dark", dropdownWindow(pinned, dark: true)),
    ]
    let fixed = [
      // Same view fed the whole catalog, to exercise the column wrap.
      ("dropdown-wide", dropdownWindow(Catalog.all)),
      ("settings", pane(.dropdown)),
      ("all", pane(.all)),
      ("general", pane(.general)),
      ("cursor", pane(.cursor)),
      ("sound", pane(.sound)),
      ("category", pane(.category(.display))),
      ("settings-dark", pane(.dropdown, dark: true)),
      ("cursor-dark", pane(.cursor, dark: true)),
      // A popover cannot be captured from its parent window, so its content
      // is hosted on its own at the width the popover gives it.
      (
        "cursor-popover",
        makeSelfSizingWindow(
          NSHostingView(
            rootView: CursorColorPicker(cursor: cursor, pointer: pointer)
              .environment(\.colorScheme, .light)))
      ),
      (
        "sound-popover",
        makeSelfSizingWindow(
          NSHostingView(
            rootView: AudioControls(audio: audio, onOpenSettings: {})
              .environment(\.colorScheme, .light)))
      ),
    ]

    // Let the first refresh land so fittingSize is meaningful, then settle
    // the content at its final size. The resize happens before the long
    // settle, not after: SwiftUI re-renders text into a resized offscreen
    // backing store lazily, and capturing right after a resize yields a
    // frame with the switches drawn but the labels missing.
    settle(seconds: 3)
    // Only the pinned dropdowns are re-sized. Resizing the full-width
    // window is what drops its text from the capture, and its initial
    // fitting size is already correct, so it is left alone.
    for (_, window) in dropdowns {
      guard let view = window.contentView else { continue }
      view.layoutSubtreeIfNeeded()
      let fit = view.fittingSize
      if fit.height > 1, fit.width > 1, abs(fit.height - view.bounds.height) > 2 {
        window.setContentSize(fit)
        view.needsDisplay = true
      }
    }
    settle(seconds: 3)

    let all = dropdowns + fixed
    for (name, window) in all { capture(window, to: "\(prefix)-\(name).png") }
    print("wrote \(all.count) PNGs under \(prefix)-")
  }

  private static func settle(seconds: TimeInterval) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
      RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
  }

  /// Mirrors how NSPopover sizes its content view controller. The window is
  /// resized again after layout settles; this is only a starting frame.
  private static func makeSelfSizingWindow(_ view: NSView, dark: Bool = false) -> NSWindow {
    let fitting = view.fittingSize
    let size = NSSize(width: max(fitting.width, 200), height: max(fitting.height, 120))
    return makeWindow(size: size, view: view, dark: dark)
  }

  private static func makeWindow(
    size: NSSize, view: NSView, dark: Bool = false, window: NSWindow? = nil
  ) -> NSWindow {
    let window =
      window
      ?? NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.titled, .resizable],
        backing: .buffered, defer: false)
    // Pin the appearance: an offscreen window inherits no effective
    // appearance, which resolves selection materials to flat black.
    let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.appearance = appearance
    window.contentView = view
    view.appearance = appearance
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

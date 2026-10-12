import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
  private var statusItem: NSStatusItem!
  private var popover: NSPopover!
  private var settingsWindow: NSWindow?
  private var refreshTimer: Timer?
  /// Dismisses the popover on a click anywhere outside it.
  private var globalMonitor: Any?
  private var stateObservation: AnyCancellable?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)

    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = statusItem.button {
      button.image = SwitchGlyph.statusItemImage()
      button.image?.accessibilityDescription = "ToggleDeck"
      button.toolTip = "ToggleDeck · Mac controls"
      button.action = #selector(statusItemClicked(_:))
      button.target = self
      button.sendAction(on: [.leftMouseDown, .rightMouseUp])
    }

    popover = NSPopover()
    popover.behavior = .transient
    popover.animates = true
    popover.delegate = self

    let host = NSHostingController(
      rootView: DropdownView(
        onOpenSettings: { [weak self] in self?.openSettings() },
        onQuit: { NSApp.terminate(nil) },
        onOpenCursorSettings: { [weak self] in self?.showSettings(initialSection: .cursor) },
        onOpenSoundSettings: { [weak self] in self?.showSettings(initialSection: .sound) },
        onClose: { [weak self] in self?.popover.performClose(nil) },
        onSizeChange: { [weak self] in self?.resizePopover(to: $0) }
      )
    )
    // Without .preferredContentSize the controller keeps the default
    // .standardBounds behaviour and never tells the popover its size
    // changed. The popover would then stay at whatever size it opened at,
    // so filtering the menu would otherwise leave the popover at its old
    // size instead of fitting the visible controls.
    host.sizingOptions = [.standardBounds, .preferredContentSize]
    popover.contentViewController = host

    stateObservation = ToggleEngine.shared.$states
      .map { $0["keepAwake"]?.isOn == true }.removeDuplicates()
      .sink { [weak self] awake in
        guard let button = self?.statusItem.button else { return }
        button.image =
          awake
          ? NSImage(
            systemSymbolName: "cup.and.saucer.fill",
            accessibilityDescription: "ToggleDeck: Keep Awake active")
          : SwitchGlyph.statusItemImage()
        button.image?.isTemplate = true
        button.toolTip = awake ? "ToggleDeck · Keep Awake active" : "ToggleDeck · Mac controls"
      }
    Task { await ToggleEngine.shared.refreshAll() }
    GlobalShortcutController.shared.start { [weak self] in self?.togglePopover() }
    startRefreshTimer()

    if let i = CommandLine.arguments.firstIndex(of: "--diagnose-popover"),
      i + 1 < CommandLine.arguments.count
    {
      diagnosePopover(writingTo: CommandLine.arguments[i + 1])
    }
  }

  /// Opens the popover the same way a click does, then records where it
  /// actually landed. Checking the geometry beats guessing at it.
  private func diagnosePopover(writingTo path: String) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
      guard let self, let button = self.statusItem.button else { exit(1) }

      self.adoptCurrentScreen()
      self.preparePopoverSize()
      self.popover.show(
        relativeTo: button.bounds, of: button,
        preferredEdge: Self.statusItemEdge)

      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        var out = "Popover geometry\n"
        let screen = DropdownLayout.layoutScreen
        let visible = screen?.visibleFrame ?? .zero
        let full = screen?.frame ?? .zero
        out += "screen frame      : \(Self.fmt(full))\n"
        out += "screen visible    : \(Self.fmt(visible))\n"
        out += "max popover height: \(Int(DropdownLayout.maxPopoverHeight()))\n"

        if let view = self.popover.contentViewController?.view {
          out +=
            "content fitting   : \(Int(view.fittingSize.width)) x \(Int(view.fittingSize.height))\n"
          out += "content bounds    : \(Self.fmt(view.bounds))\n"
        }
        out +=
          "popover contentSize: \(Int(self.popover.contentSize.width)) x \(Int(self.popover.contentSize.height))\n"

        if let win = self.popover.contentViewController?.view.window {
          let f = win.frame
          out += "popover window    : \(Self.fmt(f))\n"
          out += "window top edge   : \(Int(f.maxY))  (screen top \(Int(full.maxY)))\n"
          out +=
            "OFF SCREEN TOP    : \(f.maxY > full.maxY ? "YES, by \(Int(f.maxY - full.maxY))pt" : "no")\n"
          out +=
            "OFF SCREEN BOTTOM : \(f.minY < visible.minY ? "YES, by \(Int(visible.minY - f.minY))pt" : "no")\n"
        }
        if let b = self.statusItem.button, let w = b.window {
          out +=
            "status item frame : \(Self.fmt(w.convertToScreen(b.convert(b.bounds, to: nil))))\n"
        }

        try? out.write(toFile: path, atomically: true, encoding: .utf8)
        exit(0)
      }
    }
  }

  private static func fmt(_ r: NSRect) -> String {
    "x\(Int(r.minX)) y\(Int(r.minY)) w\(Int(r.width)) h\(Int(r.height))"
  }

  func applicationWillTerminate(_ notification: Notification) {
    refreshTimer?.invalidate()
    removeGlobalMonitor()
    stateObservation?.cancel()
    GlobalShortcutController.shared.shutdown()
    ToggleEngine.shared.flushRestarts()
    Bridges.shared.shutdown()
  }

  // MARK: Status item

  @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
    let event = NSApp.currentEvent
    // Control-click is the other canonical secondary click, and it arrives
    // as a left mouse up carrying the modifier rather than as .rightMouseUp.
    let isSecondary =
      event?.type == .rightMouseUp
      || event?.modifierFlags.contains(.control) == true
    if isSecondary {
      showContextMenu()
    } else {
      togglePopover()
    }
  }

  private func showContextMenu() {
    // The global monitor only observes other applications' events, so a
    // right-click on our own status item would otherwise leave the popover
    // sitting open behind the context menu.
    popover.performClose(nil)

    let menu = NSMenu()
    menu.addItem(withTitle: "Customize Menu…", action: #selector(openSettings), keyEquivalent: ",")
      .target = self
    menu.addItem(withTitle: "Refresh", action: #selector(refreshNow), keyEquivalent: "r")
      .target = self
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Quit ToggleDeck", action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")

    statusItem.menu = menu
    statusItem.button?.performClick(nil)
    statusItem.menu = nil  // restore left-click popover behaviour
  }

  /// NSStatusBarButton uses a flipped coordinate system, so its `minY` edge is
  /// the one against the top of the screen. Anchoring there sends the popover
  /// upward and off the display; `maxY` is the edge that hangs it downward.
  private static let statusItemEdge: NSRectEdge = .maxY

  /// Point the layout at the display the status item was clicked on. Status
  /// items appear in every screen's menu bar, and packing columns against the
  /// primary screen's height overruns a shorter secondary one.
  private func adoptCurrentScreen() {
    DropdownLayout.anchorScreen = statusItem.button?.window?.screen
  }

  private func togglePopover() {
    guard let button = statusItem.button else { return }
    if popover.isShown {
      popover.performClose(nil)
    } else {
      Task { await ToggleEngine.shared.refreshAll() }
      Task { await PointerController.shared.refresh(clearError: false) }
      Task { await AudioController.shared.refresh(clearError: false) }
      adoptCurrentScreen()
      preparePopoverSize()
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: Self.statusItemEdge)
      popover.contentViewController?.view.window?.makeKey()
      installGlobalMonitor()
    }
  }

  /// NSPopover positions from contentSize, which does not reliably follow a
  /// hosting controller's preferred size. Set it before opening and after filtering.
  private func preparePopoverSize() {
    guard let view = popover.contentViewController?.view else { return }
    view.layoutSubtreeIfNeeded()
    resizePopover(to: view.fittingSize)
  }

  private func resizePopover(to size: CGSize) {
    guard size.width > 0, size.height > 0 else { return }
    let rounded = CGSize(width: ceil(size.width), height: ceil(size.height))
    if popover.contentSize != rounded { popover.contentSize = rounded }
    DispatchQueue.main.async { [weak self] in self?.keepPopoverOnScreen() }
  }

  private func keepPopoverOnScreen() {
    guard popover.isShown,
      let window = popover.contentViewController?.view.window,
      let screen = DropdownLayout.layoutScreen
    else { return }
    let frame = window.frame
    let visible = screen.visibleFrame
    let origin = CGPoint(
      x: max(visible.minX, min(frame.minX, visible.maxX - frame.width)),
      y: max(visible.minY, min(frame.minY, visible.maxY - frame.height)))
    if origin != frame.origin { window.setFrameOrigin(origin) }
  }

  /// `.transient` closes on clicks inside other apps, but not reliably on
  /// clicks against the desktop or another menu bar item.
  private func installGlobalMonitor() {
    removeGlobalMonitor()
    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
      [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        if let button = self.statusItem.button, let window = button.window {
          let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
          if frame.contains(NSEvent.mouseLocation) { return }
        }
        self.popover.performClose(nil)
      }
    }
  }

  private func removeGlobalMonitor() {
    if let m = globalMonitor { NSEvent.removeMonitor(m) }
    globalMonitor = nil
  }

  func popoverDidClose(_ notification: Notification) {
    removeGlobalMonitor()
  }

  @objc private func refreshNow() {
    Task {
      await CursorColorController.shared.refresh()
      await PointerController.shared.refresh()
      await AudioController.shared.refresh()
      await ToggleEngine.shared.refreshAll()
    }
  }

  // MARK: Settings window

  @objc func openSettings() {
    showSettings()
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    openSettings()
    return true
  }

  private func showSettings(initialSection: SettingsSection? = nil) {
    popover.performClose(nil)

    if let window = settingsWindow {
      if let initialSection {
        window.contentViewController = NSHostingController(
          rootView: SettingsView(initialSection: initialSection))
      }
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
      return
    }

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 960, height: 660),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false
    )
    window.title = "ToggleDeck Settings"
    window.contentViewController = NSHostingController(
      rootView: SettingsView(initialSection: initialSection ?? .dropdown))
    window.isReleasedWhenClosed = false
    window.center()
    window.setFrameAutosaveName("ToggleDeckSettings")
    settingsWindow = window

    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  // MARK: Background refresh

  /// System settings change outside ToggleDeck, so a visible window re-reads
  /// on a slow timer. Nothing polls while everything is closed.
  private func startRefreshTimer() {
    refreshTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, AppSettings.shared.autoRefresh else { return }
        let windowVisible = self.settingsWindow?.isVisible ?? false
        guard self.popover.isShown || windowVisible else { return }
        await CursorColorController.shared.refresh(clearError: false)
        await PointerController.shared.refresh(clearError: false)
        await AudioController.shared.refresh(clearError: false)
        await ToggleEngine.shared.refreshAll()
      }
    }
  }
}

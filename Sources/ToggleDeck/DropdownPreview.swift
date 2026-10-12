import AppKit
import SwiftUI

/// Runs the real dropdown in a regular window with isolated, in-memory controls.
/// A separate preview bundle makes this accessible to native UI test tools.
@MainActor
enum DropdownPreview {
  static func run() {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = PreviewDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
  }

  static func render(prefix: String) {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    if let appURL = NSWorkspace.shared.urlForApplication(
      withBundleIdentifier: "com.user.toggledeck")
    {
      app.applicationIconImage = NSWorkspace.shared.icon(forFile: appURL.path)
    }
    let settings = AppSettings.preview()
    let cursor = CursorColorController.preview()
    let pointer = PointerController.preview()
    let audio = AudioController.preview()
    settings.pinned = Catalog.defaultPinned
    settings.groupDropdown = true
    for (name, scheme, search, descriptions) in [
      ("light", ColorScheme.light, "", false),
      ("dark", ColorScheme.dark, "", false),
      ("search", ColorScheme.light, "wifi", false),
      ("empty", ColorScheme.light, "doesnotexist", false),
      ("descriptions", ColorScheme.light, "", true),
      ("loading", ColorScheme.light, "", false),
      ("unavailable", ColorScheme.light, "true tone", false),
      ("error", ColorScheme.light, "wifi", false),
      ("awake", ColorScheme.dark, "", false),
      ("cursor", ColorScheme.light, "cursor", false),
    ] {
      var overrides: [String: ToggleState] = [:]
      if name == "loading" {
        overrides = Dictionary(uniqueKeysWithValues: Catalog.all.map { ($0.id, ToggleState()) })
      }
      if name == "unavailable" {
        overrides["trueTone"] = ToggleState(supported: false, stale: false)
      }
      if name == "error" {
        overrides["wifi"] = ToggleState(
          isOn: true, error: "macOS could not apply the change. Refresh or check System Settings.",
          stale: false)
      }
      if name == "awake" { overrides["keepAwake"] = ToggleState(isOn: true, stale: false) }
      let engine = ToggleEngine.preview(
        states: overrides, awakeUntil: name == "awake" ? Date().addingTimeInterval(1800) : nil)
      if name == "error" {
        engine.banner = "Wi-Fi: macOS could not apply the change. Refresh or check System Settings."
      }
      app.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
      settings.showDescriptions = descriptions
      app.appearance?.performAsCurrentDrawingAppearance {
        let content = DropdownView(
          engine: engine, settings: settings, cursor: cursor, pointer: pointer, audio: audio,
          onOpenSettings: {}, onQuit: {}, snapshotSearch: search
        )
        .environment(\.colorScheme, scheme).fixedSize()
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let cgImage = renderer.cgImage,
          let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        else {
          fatalError("Could not render \(name)")
        }
        let path = "\(prefix)-\(name).png"
        do { try data.write(to: URL(fileURLWithPath: path)) } catch {
          fatalError("Could not save \(path): \(error)")
        }
        print("\(name): \(cgImage.width / 2) × \(cgImage.height / 2) pt → \(path)")
      }
    }
  }

  @MainActor
  private final class PreviewDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var settingsWindow: NSWindow?
    private let pointer = PointerController.preview()
    private let audio = AudioController.preview()
    private let shortcut = GlobalShortcutController.preview()

    func applicationDidFinishLaunching(_ notification: Notification) {
      let settings = AppSettings.preview()
      settings.pinned = Catalog.defaultPinned
      settings.groupDropdown = true
      settings.showDescriptions = false
      let engine = ToggleEngine.preview()
      let cursor = CursorColorController.preview()
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 720, height: 720),
        styleMask: [.titled, .closable], backing: .buffered, defer: false)
      window.title = "ToggleDeck Preview"
      window.delegate = self
      window.isReleasedWhenClosed = false
      window.appearance = NSAppearance(named: .aqua)
      let view = NSHostingView(
        rootView: DropdownView(
          engine: engine, settings: settings, cursor: cursor, pointer: pointer, audio: audio,
          onOpenSettings: { [weak self] in
            self?.showSettings(engine: engine, settings: settings, cursor: cursor)
          },
          onQuit: { NSApp.terminate(nil) },
          onOpenCursorSettings: { [weak self] in
            self?.showSettings(engine: engine, settings: settings, cursor: cursor, section: .cursor)
          },
          onOpenSoundSettings: { [weak self] in
            self?.showSettings(engine: engine, settings: settings, cursor: cursor, section: .sound)
          },
          onClose: { NSApp.terminate(nil) },
          onSizeChange: { [weak window] size in
            guard size.width > 0, size.height > 0 else { return }
            window?.setContentSize(size)
          }))
      window.contentView = view
      view.layoutSubtreeIfNeeded()
      window.setContentSize(view.fittingSize)
      window.center()
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      self.window = window

      let mainMenu = NSMenu()
      let appItem = NSMenuItem()
      let appMenu = NSMenu()
      appMenu.addItem(
        withTitle: "Quit Preview", action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q")
      appItem.submenu = appMenu
      mainMenu.addItem(appItem)
      NSApp.mainMenu = mainMenu
    }

    private func showSettings(
      engine: ToggleEngine, settings: AppSettings, cursor: CursorColorController,
      section: SettingsSection = .dropdown
    ) {
      if let settingsWindow {
        settingsWindow.contentView = NSHostingView(
          rootView: SettingsView(
            initialSection: section, engine: engine, settings: settings, cursor: cursor,
            pointer: pointer, audio: audio, shortcut: shortcut))
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow.makeKeyAndOrderFront(nil)
        return
      }
      let settingsWindow = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 960, height: 660),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
      settingsWindow.title = "ToggleDeck Customize Preview"
      settingsWindow.isReleasedWhenClosed = false
      settingsWindow.contentView = NSHostingView(
        rootView: SettingsView(
          initialSection: section, engine: engine, settings: settings, cursor: cursor,
          pointer: pointer, audio: audio, shortcut: shortcut))
      settingsWindow.center()
      NSApp.activate(ignoringOtherApps: true)
      settingsWindow.makeKeyAndOrderFront(nil)
      self.settingsWindow = settingsWindow
    }

    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }
  }
}

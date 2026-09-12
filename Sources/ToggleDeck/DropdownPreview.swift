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
    let suite = "com.user.toggledeck.render.\(UUID().uuidString)"
    let store = UserDefaults(suiteName: suite)!
    defer { store.removePersistentDomain(forName: suite) }
    let settings = AppSettings(store: store)
    settings.pinned = Catalog.defaultPinned
    settings.groupDropdown = true
    let engine = ToggleEngine.preview()
    for (name, scheme, search, descriptions) in [
      ("light", ColorScheme.light, "", false),
      ("dark", ColorScheme.dark, "", false),
      ("search", ColorScheme.light, "wifi", false),
      ("empty", ColorScheme.light, "doesnotexist", false),
      ("descriptions", ColorScheme.light, "", true),
    ] {
      app.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
      settings.showDescriptions = descriptions
      app.appearance?.performAsCurrentDrawingAppearance {
        let content = DropdownView(
          engine: engine, settings: settings,
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

  private final class PreviewDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
      let store = UserDefaults(suiteName: "com.user.toggledeck.preview")!
      let settings = AppSettings(store: store)
      settings.pinned = Catalog.defaultPinned
      settings.groupDropdown = true
      settings.showDescriptions = false
      let engine = ToggleEngine.preview()
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 720, height: 720),
        styleMask: [.titled, .closable], backing: .buffered, defer: false)
      window.title = "ToggleDeck Preview"
      window.delegate = self
      window.isReleasedWhenClosed = false
      window.appearance = NSAppearance(named: .aqua)
      let view = NSHostingView(
        rootView: DropdownView(
          engine: engine, settings: settings,
          onOpenSettings: {}, onQuit: { NSApp.terminate(nil) },
          onClose: { NSApp.terminate(nil) }))
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

    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }
  }
}

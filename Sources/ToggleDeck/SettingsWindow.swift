import AppKit

/// Builds the settings window. The app and the preview share it, so the
/// window the preview shows is the window the app ships.
@MainActor
enum SettingsWindow {
  static let defaultSize = NSSize(width: 960, height: 660)

  static func make(title: String) -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: defaultSize),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    // Each pane carries its own title, so the bar stays clear and the
    // sidebar runs to the top edge. The title still names the window in
    // Mission Control and to VoiceOver.
    window.title = title
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isReleasedWhenClosed = false
    return window
  }
}

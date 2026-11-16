import Combine

/// Which settings pane is showing. The window keeps one hosting controller
/// for the whole run, so entry points route here instead of rebuilding the
/// view; rebuilding discarded search text and the Undo Reset offer, and let
/// AppKit resize the window to the new controller's fitting size.
@MainActor
final class SettingsRouter: ObservableObject {
  @Published var section: SettingsSection

  init(section: SettingsSection = .dropdown) {
    self.section = section
  }

  func request(_ section: SettingsSection) {
    // Publishing an unchanged value would still invalidate every observer.
    if self.section != section { self.section = section }
  }
}

/// The dropdown's hosting controller also lives for the whole run, so its
/// view state outlasts each popover. A new open count tells the view to
/// start fresh: the menu, not the last search, with the search field focused.
@MainActor
final class DropdownSession: ObservableObject {
  @Published private(set) var openCount = 0

  func willOpen() {
    openCount += 1
  }
}

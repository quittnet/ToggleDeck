import Foundation

extension ToggleSpec {
  var menuTitle: String {
    switch id {
    case "dockRecents": return "Recent Apps in Dock"
    case "showDesktopIcons": return "Desktop Icons"
    case "showHiddenFiles": return "Hidden Files"
    case "showAllExtensions": return "File Extensions"
    case "finderPathBar": return "Finder Path Bar"
    default: return title
    }
  }

  var menuSymbol: String {
    switch id {
    case "darkMode": return "moon.fill"
    case "nightShift": return "sun.haze.fill"
    case "trueTone": return "sun.max.fill"
    case "wifi": return "wifi"
    case "bluetooth": return "antenna.radiowaves.left.and.right"
    case "muteOutput": return "speaker.slash.fill"
    case "lowPowerMode": return "battery.50percent"
    case "keepAwake": return "cup.and.saucer.fill"
    case "dockAutohide": return "dock.rectangle"
    case "dockRecents": return "clock.arrow.circlepath"
    case "stageManager": return "rectangle.leadinghalf.inset.filled"
    case "showDesktopIcons": return "desktopcomputer"
    case "menuBarAutohide": return "menubar.rectangle"
    case "showHiddenFiles": return "eye"
    case "showAllExtensions": return "doc.text"
    case "finderPathBar": return "folder"
    case "tapToClick": return "hand.tap"
    case "naturalScrolling": return "arrow.up.arrow.down"
    case "autoCorrect": return "textformat.abc"
    case "screenshotThumbnail": return "camera.viewfinder"
    default: return category.symbol
    }
  }

  func menuSubtitle(showDescriptions: Bool) -> String? {
    if showDescriptions && !detail.isEmpty { return detail }
    if requires.contains(.admin) { return "Password required" }
    if requires.contains(.logout) { return "Log out to apply" }
    return nil
  }

  func menuHeight(showDescriptions: Bool) -> Double {
    if showDescriptions && !detail.isEmpty { return 66 }
    return menuSubtitle(showDescriptions: false) == nil ? 42 : 52
  }

  var menuHelp: String {
    ([detail] + requires.badges.map(\.0)).filter { !$0.isEmpty }.joined(separator: "\n")
  }
}

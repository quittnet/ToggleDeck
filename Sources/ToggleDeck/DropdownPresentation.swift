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

  func menuSymbol(isOn: Bool) -> String {
    guard id == "muteOutput" else { return menuSymbol }
    return isOn ? "speaker.slash.fill" : "speaker.wave.2.fill"
  }

  /// Filled, compact glyphs: each sits on a 26pt tile, where a thin or wide
  /// outline symbol reads as a smudge.
  var menuSymbol: String {
    switch id {
    case "darkMode": return "moon.fill"
    case "nightShift": return "sunset.fill"
    case "trueTone": return "sun.max.fill"
    case "reduceMotion": return "figure.walk.motion"
    case "reduceTransparency": return "square.fill.on.square.fill"
    case "squareWindowCorners": return "macwindow"
    case "wifi": return "wifi"
    case "bluetooth": return "antenna.radiowaves.left.and.right"
    case "muteOutput": return "speaker.slash.fill"
    case "lowPowerMode": return "battery.50percent"
    case "keepAwake": return "cup.and.saucer.fill"
    case "dockAutohide": return "dock.rectangle"
    case "dockRecents": return "clock.fill"
    case "stageManager": return "rectangle.leadinghalf.inset.filled"
    case "showDesktopIcons": return "desktopcomputer"
    case "menuBarAutohide": return "menubar.rectangle"
    case "showHiddenFiles": return "eye.fill"
    case "showAllExtensions": return "doc.text.fill"
    case "finderPathBar": return "folder.fill"
    case "tapToClick": return "hand.tap.fill"
    case "naturalScrolling": return "arrow.up.arrow.down"
    case "autoCorrect": return "character.cursor.ibeam"
    case "screenshotThumbnail": return "camera.viewfinder"
    default: return category.symbol
    }
  }

  func menuSubtitle(showDescriptions: Bool) -> String? {
    if showDescriptions && !detail.isEmpty { return detail }
    if requires.contains(.admin) { return "May request authorization" }
    if requires.contains(.logout) { return "Log out to apply" }
    if requires.contains(.mayNeedAppRestart) { return "May need app restart" }
    return nil
  }

  /// Exact row heights: `DropdownLayout` sizes the popover from these, so a
  /// row must render at precisely this height.
  func menuHeight(showDescriptions: Bool) -> Double {
    if showDescriptions && !detail.isEmpty { return 64 }
    return menuSubtitle(showDescriptions: false) == nil ? 40 : 50
  }

  var menuHelp: String {
    ([detail] + requires.badges.map(\.0)).filter { !$0.isEmpty }.joined(separator: "\n")
  }
}

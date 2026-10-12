import Foundation

// MARK: - Construction helpers
//
// The catalog is written as data, not code paths. Adding a setting means adding
// one line here; nothing else in the app needs to change.

private func d(
  _ id: String, _ title: String, _ detail: String, _ cat: Category,
  _ domain: String, _ key: String,
  v: PrefValue = .boolean, scope: PrefScope = .user, def: Bool = false,
  restart: [Service] = [], req: Requirements = [], kw: [String] = []
) -> ToggleSpec {
  var r = req
  if scope == .system { r.insert(.admin) }
  if Prefs.isProtectedDomain(domain) { r.insert(.fullDisk) }
  if !restart.isEmpty { r.insert(.restartApp) }
  return ToggleSpec(
    id: id, title: title, detail: detail, category: cat,
    backend: .defaults(DefaultsBacking(domain: domain, key: key, value: v, scope: scope)),
    systemDefault: def, requires: r, restarts: restart, keywords: kw)
}

private func md(
  _ id: String, _ title: String, _ detail: String, _ cat: Category,
  _ backings: [DefaultsBacking], def: Bool = false,
  restart: [Service] = [], req: Requirements = [], kw: [String] = []
) -> ToggleSpec {
  var r = req
  if backings.contains(where: { $0.scope == .system }) { r.insert(.admin) }
  if backings.contains(where: { Prefs.isProtectedDomain($0.domain) }) { r.insert(.fullDisk) }
  if !restart.isEmpty { r.insert(.restartApp) }
  return ToggleSpec(
    id: id, title: title, detail: detail, category: cat,
    backend: .multiDefaults(backings),
    systemDefault: def, requires: r, restarts: restart, keywords: kw)
}

private func sh(
  _ id: String, _ title: String, _ detail: String, _ cat: Category,
  read: String, on: String, off: String,
  parse: @escaping @Sendable (ShellResult) -> Bool? = Parse.truthy,
  def: Bool = false, restart: [Service] = [], req: Requirements = [],
  hardwareGated: Bool = false, kw: [String] = []
) -> ToggleSpec {
  var r = req
  if !restart.isEmpty { r.insert(.restartApp) }
  return ToggleSpec(
    id: id, title: title, detail: detail, category: cat,
    backend: .shell(read: read, on: on, off: off, parse: parse),
    systemDefault: def, requires: r, restarts: restart,
    unsupportedIfUnreadable: hardwareGated, keywords: kw)
}

private func br(
  _ id: String, _ title: String, _ detail: String, _ cat: Category,
  _ bridge: Bridge, req: Requirements = [], kw: [String] = []
) -> ToggleSpec {
  ToggleSpec(
    id: id, title: title, detail: detail, category: cat,
    backend: .bridge(bridge), requires: req, keywords: kw)
}

// MARK: - Output parsers for shell-backed toggles

enum Parse {
  /// "1", "true", "on", "yes", "enabled". Empty output means "key not set" and
  /// resolves to the spec's systemDefault; a failed command yields nil so the
  /// row can present itself as unsupported instead of lying.
  static let truthy: @Sendable (ShellResult) -> Bool? = { r in
    guard r.ok else { return nil }
    let s = r.out.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    switch s {
    case "1", "true", "on", "yes", "enabled": return true
    case "0", "false", "off", "no", "disabled": return false
    default: return nil
    }
  }

  /// Substring test with an explicit negative token so "disabled" never reads
  /// as a hit for "enabled".
  static func says(_ positive: String, negative: String) -> @Sendable (ShellResult) -> Bool? {
    { r in
      guard r.ok else { return nil }
      let s = r.out.lowercased()
      if s.contains(negative.lowercased()) { return false }
      if s.contains(positive.lowercased()) { return true }
      return nil
    }
  }

  /// pmset omits keys that are unset; absent means off, not unknown.
  static let pmsetFlag: @Sendable (ShellResult) -> Bool? = { r in
    guard r.ok else { return nil }
    let s = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.isEmpty { return false }
    return s == "1" ? true : (s == "0" ? false : nil)
  }

  /// Same as pmsetFlag but absence means the hardware lacks the feature.
  static let pmsetOptional: @Sendable (ShellResult) -> Bool? = { r in
    guard r.ok else { return nil }
    let s = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.isEmpty { return nil }
    return s == "1" ? true : (s == "0" ? false : nil)
  }
}

private func pmsetRead(_ key: String) -> String {
  "/usr/bin/pmset -g custom 2>/dev/null | /usr/bin/awk '$1==\"\(key)\"{print $2; exit}'"
}
private func pmsetWrite(_ key: String, _ value: Int) -> String {
  "/usr/bin/pmset -a \(key) \(value)"
}

/// Resolves the Wi-Fi interface at call time; it is en0 on most Macs but not all.
private let wifiDevice =
  "dev=$(/usr/sbin/networksetup -listallhardwareports 2>/dev/null | /usr/bin/awk '/Wi-Fi|AirPort/{getline; print $2; exit}')"

// MARK: - Everyday settings

enum Catalog {
  static let all: [ToggleSpec] =
    display + connections + power + desktop + finder + input + screenshots
  static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
  static let defaultPinned = all.map(\.id)
  static let version26DefaultPinned = all.filter { $0.id != "squareWindowCorners" }.map(\.id)
  static let versionTwoDefaultPinned = all.filter {
    $0.id != "reduceMotion" && $0.id != "reduceTransparency" && $0.id != "squareWindowCorners"
  }.map(\.id)
  static let previousDefaultPinned = [
    "lowPowerMode", "keepAwake", "bluetooth", "wifi", "darkMode", "nightShift",
    "stageManager", "dockAutohide", "menuBarAutohide", "showHiddenFiles",
    "showDesktopIcons", "showAllExtensions",
  ]
  private static let trackpadDomains = [
    "com.apple.AppleMultitouchTrackpad",
    "com.apple.driver.AppleBluetoothMultitouch.trackpad",
  ]

  static let display: [ToggleSpec] = [
    br(
      "darkMode", "Dark Mode", "Switches the system appearance to dark.", .display,
      .darkMode, req: [.automation], kw: ["dark", "light", "theme", "appearance"]),

    br(
      "nightShift", "Night Shift", "Warms the display colours to cut blue light.", .display,
      .nightShift, kw: ["blue light", "warm", "f.lux"]),

    br(
      "trueTone", "True Tone", "Adapts white balance to the ambient light.", .display,
      .trueTone, kw: ["white balance", "ambient"]),

    br(
      "reduceMotion", "Reduce Motion", "Reduces movement and animations across macOS.", .display,
      .reduceMotion, req: [.fullDisk], kw: ["animation", "accessibility", "movement"]),

    br(
      "reduceTransparency", "Reduce Transparency", "Makes translucent backgrounds more solid.",
      .display, .reduceTransparency, req: [.fullDisk],
      kw: ["glass", "opaque", "accessibility", "background"]),

    d(
      "squareWindowCorners", "Square Window Corners",
      "Sets radius to 1. Off restores defaults. Apps may need to restart.",
      .display, "NSGlobalDomain", "NSConvolutionOverride1", v: .floatOverride(on: 1),
      req: [.mayNeedAppRestart], kw: ["rounded", "radius", "window", "corners", "square"]),

  ]

  static let connections: [ToggleSpec] = [
    sh(
      "wifi", "Wi-Fi",
      "Powers the Wi-Fi radio on or off.", .connections,
      read:
        "\(wifiDevice); /usr/sbin/networksetup -getairportpower \"$dev\" 2>/dev/null | /usr/bin/awk '{print $NF}'",
      on: "\(wifiDevice); /usr/sbin/networksetup -setairportpower \"$dev\" on",
      off: "\(wifiDevice); /usr/sbin/networksetup -setairportpower \"$dev\" off",
      parse: Parse.says("on", negative: "off"), hardwareGated: true,
      kw: ["wifi", "wireless", "airport"]),

    br(
      "bluetooth", "Bluetooth", "Powers the Bluetooth radio on or off.", .connections,
      .bluetooth, kw: ["bt", "wireless", "airpods"]),

    sh(
      "muteOutput", "Mute Sound",
      "Silences system audio output.", .connections,
      read: "/usr/bin/osascript -e 'output muted of (get volume settings)'",
      on: "/usr/bin/osascript -e 'set volume output muted true'",
      off: "/usr/bin/osascript -e 'set volume output muted false'",
      req: [.automation], kw: ["mute", "volume", "silence"]),

  ]

  static let power: [ToggleSpec] = [
    sh(
      "lowPowerMode", "Low Power Mode",
      "Uses less energy to extend battery life.", .power,
      read: pmsetRead("lowpowermode"), on: pmsetWrite("lowpowermode", 1),
      off: pmsetWrite("lowpowermode", 0),
      parse: Parse.pmsetOptional, req: [.admin], hardwareGated: true,
      kw: ["battery", "lpm", "energy"]),

    br(
      "keepAwake", "Keep Awake",
      "Keeps the screen and Mac awake until you turn it off or quit ToggleDeck.", .power,
      .caffeinate, kw: ["caffeinate", "insomnia", "no sleep", "amphetamine"]),

  ]

  static let desktop: [ToggleSpec] = [
    d(
      "dockAutohide", "Auto-Hide Dock",
      "Slides the Dock away until the pointer reaches the edge.", .desktop,
      "com.apple.dock", "autohide", restart: [.dock], kw: ["hide", "dock"]),

    d(
      "dockRecents", "Show Recent Applications",
      "Adds a trailing section of recently used apps.", .desktop,
      "com.apple.dock", "show-recents", def: true, restart: [.dock], kw: ["recent"]),

    d(
      "stageManager", "Stage Manager",
      "Groups windows into a strip along the side of the screen.", .desktop,
      "com.apple.WindowManager", "GloballyEnabled", restart: [.windowManager],
      kw: ["stage", "windows"]),

    sh(
      "showDesktopIcons", "Show Icons on Desktop",
      "Shows desktop items. Turning this off keeps Finder's desktop menu available.", .desktop,
      read: "/usr/bin/defaults read com.apple.WindowManager StandardHideDesktopIcons",
      on:
        "/usr/bin/defaults write com.apple.finder CreateDesktop -bool true && /usr/bin/defaults write com.apple.WindowManager StandardHideDesktopIcons -bool false",
      off:
        "/usr/bin/defaults write com.apple.finder CreateDesktop -bool true && /usr/bin/defaults write com.apple.WindowManager StandardHideDesktopIcons -bool true",
      parse: { result in Parse.truthy(result).map { !$0 } }, def: true, restart: [.finder, .dock],
      kw: ["desktop", "clean", "icons", "context menu"]),

    d(
      "menuBarAutohide", "Auto-Hide Menu Bar",
      "Hides the menu bar until the pointer reaches the top of the screen.", .desktop,
      "NSGlobalDomain", "_HIHideMenuBar", kw: ["menubar", "hide"]),

  ]

  static let finder: [ToggleSpec] = [
    d(
      "showHiddenFiles", "Show Hidden Files",
      "Reveals dotfiles and system items in Finder.", .finder,
      "com.apple.finder", "AppleShowAllFiles", restart: [.finder], kw: ["dotfiles", "hidden"]),

    d(
      "showAllExtensions", "Show All File Extensions",
      "Always shows the filename extension.", .finder,
      "NSGlobalDomain", "AppleShowAllExtensions", restart: [.finder], kw: ["extension", "filename"]),

    d(
      "finderPathBar", "Show Path Bar",
      "Adds the folder breadcrumb along the bottom of Finder windows.", .finder,
      "com.apple.finder", "ShowPathbar", restart: [.finder], kw: ["breadcrumb", "path"]),

  ]

  static let input: [ToggleSpec] = [
    md(
      "tapToClick", "Tap to Click",
      "A tap registers as a click without pressing down.", .input,
      trackpadDomains.map { DefaultsBacking(domain: $0, key: "Clicking") }
        + [
          DefaultsBacking(
            domain: "NSGlobalDomain", key: "com.apple.mouse.tapBehavior",
            value: .intMap(on: 1, off: 0), scope: .byHost)
        ],
      req: [.logout], kw: ["tap", "click", "trackpad"]),

    d(
      "naturalScrolling", "Natural Scrolling",
      "Content follows finger direction.", .input,
      "NSGlobalDomain", "com.apple.swipescrolldirection", def: true, req: [.logout],
      kw: ["scroll", "direction", "reverse"]),

    d(
      "autoCorrect", "Autocorrect",
      "Corrects spelling automatically while you type.", .input, "NSGlobalDomain",
      "NSAutomaticSpellingCorrectionEnabled",
      def: true, kw: ["autocorrect", "spelling"]),

  ]

  static let screenshots: [ToggleSpec] = [
    d(
      "screenshotThumbnail", "Screenshot Preview",
      "The preview that appears in the corner after a capture.", .screenshots,
      "com.apple.screencapture", "show-thumbnail", def: true,
      restart: [.systemUIServer], kw: ["preview", "thumbnail"])

  ]

}

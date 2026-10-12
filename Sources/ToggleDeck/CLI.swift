import Foundation

/// Scriptable access to the same catalog the UI drives, so a setting can be
/// flipped from a shell script or a Shortcut:
///
///     ToggleDeck --get dockAutohide
///     ToggleDeck --set dockAutohide 1
///     ToggleDeck --list finder
///
/// Writes go through the same verify-after-write path as the switches, so a
/// silently rejected change exits non-zero instead of reporting success.
enum CLI {
  static func cursorColors(_ argument: String?) -> Int32 {
    func report(_ message: String, code: Int32) -> Int32 {
      FileHandle.standardError.write(Data((message + "\n").utf8))
      return code
    }
    if let argument {
      let requested: CursorColors
      if let preset = CursorPreset.allCases.first(where: {
        $0.rawValue.lowercased() == argument.lowercased()
      }) {
        requested = preset.colors
      } else if let data = argument.data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let fill = object["fill"] as? [String: Any],
        let outline = object["outline"] as? [String: Any],
        let fillColor = CursorRGB(components: fill),
        let outlineColor = CursorRGB(components: outline),
        let customized = object["customized"] as? Bool
      {
        requested = CursorColors(fill: fillColor, outline: outlineColor, customized: customized)
      } else {
        return report("Use a cursor color preset or a cursor color JSON snapshot.", code: 2)
      }
      if let error = CursorSystemColors.write(requested) { return report(error, code: 4) }
      guard let actual = CursorSystemColors.read(), actual.matches(requested),
        actual.customized == requested.customized
      else {
        return report("Could not confirm the cursor colors.", code: 5)
      }
    }
    guard let colors = CursorSystemColors.read() else {
      return report("Cursor colors are unavailable on this Mac.", code: 3)
    }
    func components(_ value: CursorRGB) -> [String: Double] {
      ["red": value.red, "green": value.green, "blue": value.blue, "alpha": value.alpha]
    }
    let object: [String: Any] = [
      "fill": components(colors.fill), "outline": components(colors.outline),
      "customized": colors.customized,
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: .sortedKeys),
      let output = String(data: data, encoding: .utf8)
    else { return report("Could not encode cursor colors.", code: 5) }
    print(output)
    return 0
  }

  static func parseBoolean(_ value: String) -> Bool? {
    switch value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
    case "1", "true", "on", "yes": return true
    case "0", "false", "off", "no": return false
    default: return nil
    }
  }

  private static func sessionOnly() -> Int32 {
    FileHandle.standardError.write(
      Data("Keep Awake belongs to the running menu bar app. Use its switch.\n".utf8))
    return 3
  }

  static func get(_ id: String) -> Int32 {
    guard let spec = Catalog.byID[id] else {
      FileHandle.standardError.write(Data("unknown setting: \(id)\n".utf8))
      return 2
    }
    guard id != "keepAwake" else { return sessionOnly() }
    let st = ToggleEngine.read(spec)
    guard st.supported else {
      FileHandle.standardError.write(Data("unavailable on this Mac: \(id)\n".utf8))
      return 3
    }
    print(st.isOn ? "1" : "0")
    return 0
  }

  static func set(_ id: String, _ value: String) -> Int32 {
    guard let spec = Catalog.byID[id] else {
      FileHandle.standardError.write(Data("unknown setting: \(id)\n".utf8))
      return 2
    }
    guard let on = parseBoolean(value) else {
      FileHandle.standardError.write(
        Data("invalid value: use 1/0, true/false, on/off, or yes/no\n".utf8))
      return 2
    }
    guard id != "keepAwake" else { return sessionOnly() }

    let before = ToggleEngine.read(spec)
    guard before.supported else {
      FileHandle.standardError.write(Data("unavailable on this Mac: \(id)\n".utf8))
      return 3
    }

    if let failure = ToggleEngine.performWriteForCLI(spec, on: on) {
      FileHandle.standardError.write(Data("write failed: \(failure)\n".utf8))
      return 4
    }

    if !spec.restarts.isEmpty {
      Shell.run(spec.restarts.map(\.killCommand).joined(separator: "; "), timeout: 10)
    }

    usleep(400_000)
    let after = ToggleEngine.read(spec, verifyingWrite: true)
    if let error = ToggleEngine.verificationError(spec, requested: on, actual: after) {
      FileHandle.standardError.write(Data("verification failed: \(error)\n".utf8))
      return 5
    }
    print(on ? "1" : "0")
    return 0
  }

  static func list(_ filter: String?) -> Int32 {
    for spec in SettingSearch.results(in: Catalog.all, query: filter ?? "") {
      let flags = spec.requires.badges.map(\.0).joined(separator: ",")
      print(
        "\(spec.id.padding(toLength: 30, withPad: " ", startingAt: 0)) "
          + "\(spec.category.rawValue.padding(toLength: 26, withPad: " ", startingAt: 0)) \(flags)")
    }
    return 0
  }

  private static let usageText = """
    ToggleDeck: everyday macOS settings from the menu bar

    With no arguments, runs as a menu bar app.
    Keep Awake is available in the menu bar app only.

      --get <id>              print 1 or 0
      --set <id> <1|0>        change a setting, verified after writing
      --list [filter]         list setting ids
      --cursor-colors [preset|JSON]  read or change pointer colors
      --selftest [--verbose] [--out PATH]
      --render <prefix>       write UI screenshots (debugging)
    """

  static func usage() -> Int32 {
    print(usageText)
    return 0
  }

  /// Reports a malformed invocation on stderr, usage included, and returns exit
  /// code 2. Without this an argument that was missing its value fell through to
  /// the menu bar app, leaving the caller waiting on a process that never exits.
  static func argumentError(_ message: String) -> Int32 {
    FileHandle.standardError.write(Data("\(message)\n\n\(usageText)\n".utf8))
    return 2
  }
}

import Foundation

/// Scriptable access to the same catalog the UI drives, so a setting can be
/// flipped from a shell script or a Shortcut:
///
///     ToggleDeck --get dockAutohide
///     ToggleDeck --set dockAutohide 1
///     ToggleDeck --list finder
///     ToggleDeck --toggle darkMode
///     ToggleDeck --status --json
///
/// Writes go through the same verify-after-write path as the switches, so a
/// silently rejected change exits non-zero instead of reporting success.
enum CLI {
  /// What the command line asked for. Parsing is separate from running so every
  /// accepted and rejected shape can be tested without starting anything.
  enum Invocation: Equatable {
    case menuBarApp
    case help
    case version
    case get(String)
    case set(String, String)
    case toggle(String)
    case list(String?)
    case status(json: Bool)
    case cursorColors(String?)
    case selfTest(verbose: Bool, out: String?)
    case makeIcon(String)
    case render(String)
    case renderDropdown(String)
    case previewDropdown
    case invalid(String)
  }

  /// `arguments` excludes argv[0]. Every command has an exact arity: a leftover
  /// token is a typo, and acting on the rest of the line would hide it (a stray
  /// `--set` after `--list` used to perform a write).
  static func parse(_ arguments: [String]) -> Invocation {
    guard let command = arguments.first else { return .menuBarApp }
    let rest = Array(arguments.dropFirst())

    func exactly(_ count: Int, _ need: String, _ make: () -> Invocation) -> Invocation {
      if rest.count < count { return .invalid("\(command) needs \(need).") }
      if rest.count > count {
        return .invalid("unrecognised arguments: \(rest.dropFirst(count).joined(separator: " "))")
      }
      return make()
    }
    /// Ids and filters never start with `--`; a token that does is a mistyped flag.
    func flagLike(_ token: String) -> Bool { token.hasPrefix("--") }

    switch command {
    case "--help", "-h": return exactly(0, "no arguments") { .help }
    case "--version": return exactly(0, "no arguments") { .version }
    case "--get":
      return exactly(1, "a setting id") {
        flagLike(rest[0]) ? .invalid("--get needs a setting id.") : .get(rest[0])
      }
    case "--set":
      return exactly(2, "a setting id and a value") {
        flagLike(rest[0])
          ? .invalid("--set needs a setting id and a value.") : .set(rest[0], rest[1])
      }
    case "--toggle":
      return exactly(1, "a setting id") {
        flagLike(rest[0]) ? .invalid("--toggle needs a setting id.") : .toggle(rest[0])
      }
    case "--list":
      if rest.count > 1 { return .invalid("--list accepts at most one filter.") }
      if let filter = rest.first, flagLike(filter) {
        return .invalid("unrecognised arguments: \(filter)")
      }
      return .list(rest.first)
    case "--status":
      if rest.isEmpty { return .status(json: false) }
      if rest == ["--json"] { return .status(json: true) }
      return .invalid("--status accepts only --json.")
    case "--cursor-colors":
      if rest.count > 1 { return .invalid("--cursor-colors accepts at most one value.") }
      return .cursorColors(rest.first)
    case "--selftest":
      var verbose = false
      var out: String?
      var i = 0
      while i < rest.count {
        switch rest[i] {
        case "--verbose" where !verbose:
          verbose = true
        case "--out" where out == nil:
          guard i + 1 < rest.count, !flagLike(rest[i + 1]) else {
            return .invalid("--out needs a file path.")
          }
          out = rest[i + 1]
          i += 1
        default:
          return .invalid("unrecognised arguments: \(rest[i...].joined(separator: " "))")
        }
        i += 1
      }
      return .selfTest(verbose: verbose, out: out)
    case "--make-icon": return exactly(1, "an output path") { .makeIcon(rest[0]) }
    case "--render": return exactly(1, "an output prefix") { .render(rest[0]) }
    case "--render-dropdown": return exactly(1, "an output prefix") { .renderDropdown(rest[0]) }
    case "--preview-dropdown": return exactly(0, "no arguments") { .previewDropdown }
    // The app delegate reads this flag itself, so the parser only has to let the
    // app start with it.
    case "--diagnose-popover": return exactly(1, "an output path") { .menuBarApp }
    default: return .invalid("unrecognised arguments: \(arguments.joined(separator: " "))")
    }
  }

  /// Everything `--get`, `--set`, `--toggle`, and `--status` touch outside the
  /// process, so tests can drive them with fakes and never change the Mac.
  struct Environment {
    var read: (ToggleSpec) -> ToggleState
    var write: (ToggleSpec, Bool) -> String?
    var verify: (ToggleSpec, Bool) async -> ToggleState
    var restart: (ToggleSpec) -> Void
    var restartsEnabled: () -> Bool
    var out: (String) -> Void
    var err: (String) -> Void

    static var live: Environment {
      Environment(
        read: { ToggleEngine.read($0) },
        write: { ToggleEngine.performWriteForCLI($0, on: $1) },
        verify: { await ToggleEngine.verify($0, requested: $1) },
        restart: { spec in
          Shell.run(spec.restarts.map(\.killCommand).joined(separator: "; "), timeout: 10)
        },
        // The menu bar path honors this preference; `AppSettings` is main-actor
        // isolated and manages the login item, so read the stored value directly.
        restartsEnabled: {
          UserDefaults.standard.object(forKey: "restartServices") as? Bool ?? true
        },
        out: { print($0) },
        err: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) })
    }
  }

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

  private static func sessionOnly(_ env: Environment) -> Int32 {
    env.err("Keep Awake belongs to the running menu bar app. Use its switch.")
    return 3
  }

  static func get(_ id: String, env: Environment = .live) -> Int32 {
    guard let spec = Catalog.byID[id] else {
      env.err("unknown setting: \(id)")
      return 2
    }
    guard id != "keepAwake" else { return sessionOnly(env) }
    let st = env.read(spec)
    guard st.supported else {
      env.err("unavailable on this Mac: \(id)")
      return 3
    }
    env.out(st.isOn ? "1" : "0")
    return 0
  }

  static func set(_ id: String, _ value: String, env: Environment = .live) async -> Int32 {
    await change(id, to: .value(value), env: env)
  }

  static func toggle(_ id: String, env: Environment = .live) async -> Int32 {
    await change(id, to: .flip, env: env)
  }

  private enum Target {
    case value(String)
    case flip
  }

  /// One path for `--set` and `--toggle`, so a flip gets the same write,
  /// service restart, and verification as an explicit value.
  private static func change(_ id: String, to target: Target, env: Environment) async -> Int32 {
    guard let spec = Catalog.byID[id] else {
      env.err("unknown setting: \(id)")
      return 2
    }
    var requested: Bool?
    if case .value(let value) = target {
      guard let on = parseBoolean(value) else {
        env.err("invalid value: use 1/0, true/false, on/off, or yes/no")
        return 2
      }
      requested = on
    }
    guard id != "keepAwake" else { return sessionOnly(env) }

    let before = env.read(spec)
    guard before.supported else {
      env.err("unavailable on this Mac: \(id)")
      return 3
    }
    let on = requested ?? !before.isOn

    if let failure = env.write(spec, on) {
      env.err("write failed: \(failure)")
      return 4
    }

    if !spec.restarts.isEmpty, env.restartsEnabled() { env.restart(spec) }

    let after = await env.verify(spec, on)
    if let error = ToggleEngine.verificationError(spec, requested: on, actual: after) {
      env.err("verification failed: \(error)")
      return 5
    }
    env.out(on ? "1" : "0")
    return 0
  }

  /// Every catalog entry in order, each read once. Keep Awake lives in the
  /// running app's memory, so another process reports it as unavailable.
  static func status(json: Bool, env: Environment = .live) -> Int32 {
    let rows: [(spec: ToggleSpec, on: Bool?)] = Catalog.all.map { spec in
      guard spec.id != "keepAwake" else { return (spec, nil) }
      let st = env.read(spec)
      return (spec, st.supported ? st.isOn : nil)
    }
    if json {
      let objects: [[String: Any]] = rows.map {
        [
          "id": $0.spec.id, "title": $0.spec.title, "category": $0.spec.category.rawValue,
          "available": $0.on != nil, "on": $0.on.map { $0 as Any } ?? NSNull(),
        ]
      }
      guard let data = try? JSONSerialization.data(withJSONObject: objects, options: .sortedKeys),
        let text = String(data: data, encoding: .utf8)
      else {
        env.err("Could not encode status.")
        return 5
      }
      env.out(text)
    } else {
      for row in rows {
        let state = row.on.map { $0 ? "on" : "off" } ?? "unavailable"
        env.out("\(row.spec.id.padding(toLength: 30, withPad: " ", startingAt: 0)) \(state)")
      }
    }
    return 0
  }

  static func version() -> Int32 {
    print("ToggleDeck \(AppVersion.display)")
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

  static let usageText = """
    ToggleDeck: everyday macOS settings from the menu bar

    With no arguments, runs as a menu bar app.
    Keep Awake is available in the menu bar app only.

      --get <id>              print 1 or 0
      --set <id> <1|0>        change a setting, verified after writing
      --toggle <id>           flip a setting, verified after writing
      --list [filter]         list setting ids
      --status [--json]       state of every setting
      --cursor-colors [preset|JSON]  read or change pointer colors
      --selftest [--verbose] [--out PATH]
      --make-icon <path>      write the app icon
      --render <prefix>       write UI screenshots (debugging)
      --render-dropdown <prefix>  write dropdown previews (debugging)
      --preview-dropdown      open the dropdown preview window
      --version               print the version
      --help, -h              print this text
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

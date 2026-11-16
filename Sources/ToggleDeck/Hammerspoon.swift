import Foundation

/// Controls that drive a script running inside Hammerspoon, through its `hs`
/// command-line tool. ToggleDeck installs none of this: the user's own
/// `init.lua` loads each script and keeps what it returns in the global table
/// `Z`, and every script returns a table with a `stop()` function.
enum Hammerspoon {
  /// Where the `hs` command-line tool may be. Homebrew, /usr/local, and the
  /// app bundle each put it somewhere else, and the menu bar app's PATH is
  /// minimal, so it is found at call time. Entries are shell words.
  static let tools = [
    "/opt/homebrew/bin/hs", "/usr/local/bin/hs",
    "/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs",
    "\"$HOME/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs\"",
  ]

  static let unavailableNote = "Unavailable · needs Hammerspoon running"

  /// Shell command that runs `lua` in the running Hammerspoon. Exit 69 means
  /// no tool was found, or Hammerspoon is not running (the tool's own code),
  /// and reads as unavailable. The chunk sits inside single quotes, so it
  /// must not contain any. The tool waits for its standard input to end, so
  /// it is given none: its timeout does not cover that wait.
  static func command(_ lua: String, tools: [String] = Hammerspoon.tools) -> String {
    "hs=; for p in \(tools.joined(separator: " ")); do [ -x \"$p\" ] && hs=\"$p\" && break; done; "
      + "[ -n \"$hs\" ] || exit 69; \"$hs\" -q -t 3 -c '\(lua)' < /dev/null"
  }

  /// One script, as `init.lua` loads it: `Z.<field> = require("<name>")`.
  struct Module: Sendable {
    /// The key in `Z` that holds the module.
    let field: String
    /// The name `init.lua` passes to `require`.
    let name: String
    /// Lua expression that is true while the script is running. It may use
    /// `Z.<field>`; a failure to evaluate it reads as "not loaded".
    let running: String

    /// "true" or "false" while the script is loaded, "missing" otherwise.
    var read: String {
      #"if Z and Z.\#(field) then local ok, running = pcall(function() return \#(running) end); if ok and running ~= nil then return tostring(running) end end return "missing""#
    }

    var off: String { #"if Z and Z.\#(field) then Z.\#(field).stop() end"# }

    /// Stops the running copy first so a second watcher never stacks up, then
    /// loads the script again, which starts it.
    var on: String {
      #"Z = Z or {}; if Z.\#(field) then Z.\#(field).stop() end; package.loaded["\#(name)"] = nil; Z.\#(field) = require("\#(name)")"#
    }
  }

  /// Keeps the pointer from reaching the bottom edge unless Command is held.
  static let commandDock = Module(
    field: "commandDock", name: "command-dock", running: "Z.commandDock.listener:isEnabled()")

  /// Copies every new screenshot to the clipboard.
  static let screenshotClipboard = Module(
    field: "shotClip", name: "shotclip", running: "Z.shotClip.status().running")
}

import AppKit
import Foundation
import Testing

@testable import ToggleDeck

/// The two controls that drive scripts in the user's Hammerspoon.
struct HammerspoonControlTests {
  private static let ids = ["dockCommand", "screenshotClipboard"]
  private static let modules = [Hammerspoon.commandDock, Hammerspoon.screenshotClipboard]

  private func spec(_ id: String) -> ToggleSpec { Catalog.byID[id]! }

  // MARK: Catalog and menu

  @Test
  func testControlsAreOptInAndNeverPartOfADefaultMenu() {
    for id in Self.ids {
      let spec = spec(id)
      #expect(spec.optIn)
      #expect(spec.unsupportedIfUnreadable)
      #expect(spec.unavailableNote == Hammerspoon.unavailableNote)
      for defaults in [
        Catalog.defaultPinned, Catalog.version26DefaultPinned, Catalog.versionTwoDefaultPinned,
      ] {
        #expect(!defaults.contains(id))
      }
    }
    #expect(spec("dockCommand").category == .desktop)
    #expect(spec("screenshotClipboard").category == .screenshots)
    // Nothing else is opt-in, so nothing else drops out of the default menu.
    #expect(Catalog.defaultSpecs.count == Catalog.all.count - Self.ids.count)
  }

  @Test
  func testDetailsNameTheBehaviourAndTheDependency() {
    let dock = spec("dockCommand")
    #expect(dock.detail.contains("Command"))
    #expect(dock.detail.contains("bottom of the screen"))
    let clipboard = spec("screenshotClipboard")
    #expect(clipboard.detail.contains("clipboard"))
    #expect(clipboard.detail.contains("keeps the file"))
    for id in Self.ids { #expect(spec(id).detail.contains("Hammerspoon")) }
    #expect(
      SettingSearch.results(in: Catalog.all, query: "hammerspoon dock").map(\.id) == ["dockCommand"]
    )
    #expect(
      SettingSearch.results(in: Catalog.all, query: "clipboard screenshot").map(\.id)
        == ["screenshotClipboard"])
  }

  @Test
  func testPinnedControlsSurviveEveryMigrationPath() {
    let withThem = Catalog.defaultPinned + Self.ids
    #expect(AppSettings.migratedPins(withThem, schemaVersion: 1) == withThem)
    // An older menu with extras after the original defaults keeps them.
    #expect(
      AppSettings.migratedPins(Catalog.previousDefaultPinned + Self.ids)
        == Catalog.defaultPinned + Self.ids)
    // The menu of someone who never pinned them is not changed.
    #expect(
      AppSettings.migratedPins(Catalog.defaultPinned, schemaVersion: 1) == Catalog.defaultPinned)
  }

  @Test
  func testControlsSitNextToTheirRelatives() {
    let desktop = Catalog.desktop.map(\.id)
    #expect(desktop.firstIndex(of: "dockCommand") == desktop.firstIndex(of: "dockAutohide")! + 1)
    #expect(Catalog.screenshots.map(\.id) == ["screenshotThumbnail", "screenshotClipboard"])
  }

  // MARK: Reading state

  @Test
  func testReadAnswersMapToOnOffAndUnavailable() {
    for id in Self.ids {
      let spec = spec(id)
      func state(_ status: Int32, _ out: String = "") -> ToggleState {
        ToggleEngine.shellState(spec, result: ShellResult(status: status, out: out))
      }
      #expect(state(0, "true").isOn && state(0, "true").supported)
      #expect(!state(0, "false").isOn && state(0, "false").supported)
      // The script is not loaded, Hammerspoon is not running, the tool is
      // missing, or the call timed out: none of these may read as OFF.
      for unavailable in [state(0, "missing"), state(0, ""), state(69), state(1), state(-2)] {
        #expect(!unavailable.supported)
      }
    }
  }

  // MARK: The Lua that runs

  @Test
  func testLuaChunksFitInsideSingleQuotes() {
    for module in Self.modules {
      for lua in [module.read, module.on, module.off] {
        #expect(!lua.contains("'"))
        #expect(!lua.contains("\n"))
      }
    }
  }

  @Test
  func testChunksNameTheirOwnModule() {
    let dock = Hammerspoon.commandDock
    #expect(dock.on.contains("Z.commandDock = require(\"command-dock\")"))
    #expect(dock.on.contains("package.loaded[\"command-dock\"] = nil"))
    #expect(dock.off.contains("Z.commandDock.stop()"))
    #expect(dock.read.contains("Z.commandDock.listener:isEnabled()"))
    let shot = Hammerspoon.screenshotClipboard
    #expect(shot.on.contains("Z.shotClip = require(\"shotclip\")"))
    #expect(shot.on.contains("package.loaded[\"shotclip\"] = nil"))
    #expect(shot.off.contains("Z.shotClip.stop()"))
    #expect(shot.read.contains("Z.shotClip.status().running"))
    // Turning on stops the old copy first, so watchers never stack.
    for module in Self.modules {
      let on = module.on
      let stop = on.range(of: "stop()")?.lowerBound
      let load = on.range(of: "require(")?.lowerBound
      #expect(stop != nil && load != nil && stop! < load!)
    }
  }

  // MARK: The command that runs them

  @Test
  func testEveryCommandIsValidShell() throws {
    for id in Self.ids {
      guard case .shell(let read, let on, let off, _) = spec(id).backend else {
        Issue.record("\(id) must be shell backed")
        continue
      }
      for command in [read, on, off] {
        let file = FileManager.default.temporaryDirectory
          .appendingPathComponent("hammerspoon-control-\(UUID().uuidString).sh")
        try command.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let result = Shell.run("/bin/sh -n '\(file.path)'")
        #expect(result.ok, Comment(rawValue: "\(id): \(result.message)"))
      }
    }
  }

  @Test
  func testCommandPassesTheChunkToTheFirstUsableTool() throws {
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("hammerspoon-tools-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let tool = folder.appendingPathComponent("hs")
    try "#!/bin/sh\nprintf '%s\\n' \"$@\"\n".write(to: tool, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)

    // An absent first candidate is skipped; the quoted one is used.
    let lua = Hammerspoon.screenshotClipboard.read
    let result = Shell.run(Hammerspoon.command(lua, tools: ["/nonexistent/hs", "'\(tool.path)'"]))
    #expect(result.ok)
    #expect(result.out.split(separator: "\n").map(String.init) == ["-q", "-t", "3", "-c", lua])
  }

  @Test
  func testCommandExitsWith69WhenNoToolExists() {
    let result = Shell.run(
      Hammerspoon.command(Hammerspoon.commandDock.on, tools: ["/nonexistent/hs"]))
    #expect(result.status == 69)
    #expect(result.out.isEmpty)
  }

  @Test
  func testToolIsGivenNoStandardInput() {
    // `hs` waits for its standard input to end, and its own timeout does not
    // cover that wait, so a caller with an open pipe would hang it.
    for module in Self.modules {
      #expect(Hammerspoon.command(module.read).hasSuffix("< /dev/null"))
    }
  }

  @Test
  func testHomeBasedCandidateExpandsAtRunTime() {
    // The one candidate under $HOME is quoted so the shell expands it.
    #expect(Hammerspoon.tools.contains { $0.hasPrefix("\"$HOME/") && $0.hasSuffix("/hs\"") })
  }

  // MARK: Presentation

  @Test
  func testTilesAndWording() {
    for (id, symbol, title) in [
      ("dockCommand", "command.square.fill", "Dock Needs Command"),
      ("screenshotClipboard", "doc.on.clipboard.fill", "Copy Screenshots to Clipboard"),
    ] {
      let spec = spec(id)
      #expect(spec.menuSymbol == symbol)
      #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil)
      #expect(spec.menuTitle == title)
      #expect(spec.unavailableNote?.contains("Hammerspoon") == true)
    }
  }
}

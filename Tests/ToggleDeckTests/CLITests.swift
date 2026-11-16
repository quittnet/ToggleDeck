import Foundation
import Testing

@testable import ToggleDeck

/// Records what a fake environment was asked to do. Tests run one at a time
/// per instance, so no locking is needed.
private final class Harness {
  var states: [String: ToggleState] = [:]
  var writes: [(String, Bool)] = []
  var restarts: [String] = []
  var restartsEnabled = true
  var writeFailure: String?
  /// What verify reports; nil echoes the requested value back.
  var verifyOverride: ToggleState?
  var reads: [String] = []
  var out: [String] = []
  var err: [String] = []

  func env() -> CLI.Environment {
    CLI.Environment(
      read: { spec in
        self.reads.append(spec.id)
        return self.states[spec.id] ?? ToggleState(isOn: false, supported: true, stale: false)
      },
      write: { spec, on in
        self.writes.append((spec.id, on))
        return self.writeFailure
      },
      verify: { _, requested in
        self.verifyOverride ?? ToggleState(isOn: requested, supported: true, stale: false)
      },
      restart: { self.restarts.append($0.id) },
      restartsEnabled: { self.restartsEnabled },
      out: { self.out.append($0) },
      err: { self.err.append($0) })
  }

  func state(_ id: String, on: Bool, supported: Bool = true) {
    states[id] = ToggleState(isOn: on, supported: supported, stale: false)
  }
}

@Suite("CLI argument parsing")
struct CLIParseTests {
  @Test
  func acceptedShapes() {
    #expect(CLI.parse([]) == .menuBarApp)
    #expect(CLI.parse(["--help"]) == .help)
    #expect(CLI.parse(["-h"]) == .help)
    #expect(CLI.parse(["--version"]) == .version)
    #expect(CLI.parse(["--get", "darkMode"]) == .get("darkMode"))
    #expect(CLI.parse(["--set", "wifi", "0"]) == .set("wifi", "0"))
    #expect(CLI.parse(["--toggle", "wifi"]) == .toggle("wifi"))
    #expect(CLI.parse(["--list"]) == .list(nil))
    #expect(CLI.parse(["--list", "finder"]) == .list("finder"))
    #expect(CLI.parse(["--status"]) == .status(json: false))
    #expect(CLI.parse(["--status", "--json"]) == .status(json: true))
    #expect(CLI.parse(["--cursor-colors"]) == .cursorColors(nil))
    #expect(CLI.parse(["--cursor-colors", "blue"]) == .cursorColors("blue"))
    #expect(CLI.parse(["--selftest"]) == .selfTest(verbose: false, out: nil))
    #expect(CLI.parse(["--selftest", "--verbose"]) == .selfTest(verbose: true, out: nil))
    #expect(CLI.parse(["--selftest", "--out", "r.txt"]) == .selfTest(verbose: false, out: "r.txt"))
    #expect(
      CLI.parse(["--selftest", "--verbose", "--out", "r.txt"])
        == .selfTest(verbose: true, out: "r.txt"))
    #expect(
      CLI.parse(["--selftest", "--out", "r.txt", "--verbose"])
        == .selfTest(verbose: true, out: "r.txt"))
    #expect(CLI.parse(["--make-icon", "i.png"]) == .makeIcon("i.png"))
    #expect(CLI.parse(["--render", "p"]) == .render("p"))
    #expect(CLI.parse(["--render-dropdown", "p"]) == .renderDropdown("p"))
    #expect(CLI.parse(["--preview-dropdown"]) == .previewDropdown)
  }

  @Test
  func diagnosePopoverStartsTheMenuBarApp() {
    #expect(CLI.parse(["--diagnose-popover", "/tmp/x.txt"]) == .menuBarApp)
    guard case .invalid = CLI.parse(["--diagnose-popover"]) else {
      Issue.record("missing path was accepted")
      return
    }
    guard case .invalid = CLI.parse(["--diagnose-popover", "a", "b"]) else {
      Issue.record("trailing argument was accepted")
      return
    }
  }

  @Test(
    arguments: [
      ["--bogus"], ["bogus"], ["--get"], ["--get", "darkMode", "--bogus"],
      ["--get", "--bogus"], ["--set"], ["--set", "wifi"], ["--set", "wifi", "0", "extra"],
      ["--set", "darkMode", "1", "--selftest"], ["--toggle"], ["--toggle", "a", "b"],
      ["--list", "a", "b"], ["--list", "--set", "wifi", "0"], ["--list", "--bogus"],
      ["--status", "--bogus"], ["--status", "--json", "x"], ["--help", "x"],
      ["--version", "x"], ["--cursor-colors", "a", "b"], ["--selftest", "--out"],
      ["--selftest", "--out", "--verbose"], ["--selftest", "--verbose", "--verbose"],
      ["--selftest", "extra"], ["--make-icon"], ["--make-icon", "a", "b"], ["--render"],
      ["--render", "a", "b"], ["--render-dropdown"], ["--preview-dropdown", "x"],
    ])
  func rejectedShapes(arguments: [String]) {
    guard case .invalid(let message) = CLI.parse(arguments) else {
      Issue.record("accepted \(arguments)")
      return
    }
    #expect(!message.isEmpty)
  }

  @Test
  func usageListsEveryCommand() {
    let text = CLI.usageText
    for flag in [
      "--get", "--set", "--toggle", "--list", "--status", "--cursor-colors", "--selftest",
      "--make-icon", "--render", "--render-dropdown", "--preview-dropdown", "--version",
      "--help",
    ] {
      #expect(text.contains(flag), "usage omits \(flag)")
    }
  }
}

@Suite("CLI commands with a fake environment")
struct CLICommandTests {
  @Test
  func toggleFlipsTheReadValueAndVerifies() async {
    for current in [true, false] {
      let h = Harness()
      h.state("darkMode", on: current)
      #expect(await CLI.toggle("darkMode", env: h.env()) == 0)
      #expect(h.writes.count == 1 && h.writes[0] == ("darkMode", !current))
      #expect(h.out == [current ? "0" : "1"])
    }
  }

  @Test
  func setWritesTheRequestedValue() async {
    let h = Harness()
    h.state("darkMode", on: true)
    #expect(await CLI.set("darkMode", "on", env: h.env()) == 0)
    #expect(h.writes[0] == ("darkMode", true))
    #expect(h.out == ["1"])
  }

  @Test(arguments: [true, false])
  func unavailableIsExit3(toggling: Bool) async {
    let h = Harness()
    h.state("wifi", on: false, supported: false)
    let code =
      toggling
      ? await CLI.toggle("wifi", env: h.env()) : await CLI.set("wifi", "1", env: h.env())
    #expect(code == 3)
    #expect(h.writes.isEmpty)
  }

  @Test(arguments: [true, false])
  func keepAwakeIsExit3(toggling: Bool) async {
    let h = Harness()
    let code =
      toggling
      ? await CLI.toggle("keepAwake", env: h.env()) : await CLI.set("keepAwake", "1", env: h.env())
    #expect(code == 3)
    #expect(h.writes.isEmpty && h.reads.isEmpty)
  }

  @Test(arguments: [true, false])
  func unknownIdIsExit2(toggling: Bool) async {
    let h = Harness()
    let code =
      toggling
      ? await CLI.toggle("nope", env: h.env()) : await CLI.set("nope", "1", env: h.env())
    #expect(code == 2)
    #expect(h.writes.isEmpty)
  }

  @Test(arguments: [true, false])
  func writeFailureIsExit4(toggling: Bool) async {
    let h = Harness()
    h.writeFailure = "denied"
    let code =
      toggling
      ? await CLI.toggle("darkMode", env: h.env()) : await CLI.set("darkMode", "1", env: h.env())
    #expect(code == 4)
    #expect(h.out.isEmpty)
  }

  @Test(arguments: [true, false])
  func verificationMismatchIsExit5(toggling: Bool) async {
    let h = Harness()
    h.state("darkMode", on: false)
    h.verifyOverride = ToggleState(isOn: false, supported: true, stale: false)
    let code =
      toggling
      ? await CLI.toggle("darkMode", env: h.env()) : await CLI.set("darkMode", "1", env: h.env())
    #expect(code == 5)
    #expect(h.out.isEmpty)
  }

  @Test
  func setHonorsTheRestartPreference() async throws {
    let spec = try #require(Catalog.all.first { !$0.restarts.isEmpty })
    let off = Harness()
    off.restartsEnabled = false
    #expect(await CLI.set(spec.id, "1", env: off.env()) == 0)
    #expect(off.restarts.isEmpty)

    let on = Harness()
    #expect(await CLI.set(spec.id, "1", env: on.env()) == 0)
    #expect(on.restarts == [spec.id])
  }

  @Test
  func statusTextListsEveryEntryInCatalogOrder() throws {
    let h = Harness()
    h.state("darkMode", on: true)
    h.state("wifi", on: false, supported: false)
    #expect(CLI.status(json: false, env: h.env()) == 0)
    #expect(h.out.count == Catalog.all.count)
    func line(_ id: String) throws -> String {
      try #require(h.out.first { $0.hasPrefix(id + " ") })
    }
    #expect(try line("darkMode").hasSuffix(" on"))
    #expect(try line("wifi").hasSuffix(" unavailable"))
    #expect(try line("keepAwake").hasSuffix(" unavailable"))
    #expect(try line("nightShift").hasSuffix(" off"))
    #expect(h.out.map { String($0.prefix(while: { $0 != " " })) } == Catalog.all.map(\.id))
    #expect(!h.reads.contains("keepAwake"))
    #expect(h.reads.count == Catalog.all.count - 1)
  }

  @Test
  func statusJSONHasTheDocumentedShape() throws {
    let h = Harness()
    h.state("darkMode", on: true)
    h.state("wifi", on: false, supported: false)
    #expect(CLI.status(json: true, env: h.env()) == 0)
    let data = try #require(h.out.first?.data(using: .utf8))
    let array = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    #expect(array.map { $0["id"] as? String } == Catalog.all.map(\.id))
    for entry in array {
      #expect(Set(entry.keys) == ["id", "title", "category", "available", "on"])
    }

    let dark = try #require(array.first { $0["id"] as? String == "darkMode" })
    #expect(dark["available"] as? Bool == true && dark["on"] as? Bool == true)
    #expect(dark["category"] as? String == Catalog.byID["darkMode"]?.category.rawValue)
    for id in ["wifi", "keepAwake"] {
      let entry = try #require(array.first { $0["id"] as? String == id })
      #expect(entry["available"] as? Bool == false)
      #expect(entry["on"] is NSNull)
    }
    let text = try #require(h.out.first)
    #expect(
      text.range(of: "\"available\"")!.lowerBound < text.range(of: "\"category\"")!.lowerBound)
  }
}

@MainActor
@Suite("Self-test exit status")
struct SelfTestTests {
  @Test
  func unwritableOutPathIsReported() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("toggledeck-selftest-\(UUID().uuidString)")
    let path = dir.appendingPathComponent("missing/report.txt").path
    #expect(SelfTest.deliver("report", to: path) != nil)
    #expect(!FileManager.default.fileExists(atPath: dir.path))
  }

  @Test
  func writablePathSucceeds() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("toggledeck-selftest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appendingPathComponent("report.txt").path
    #expect(SelfTest.deliver("report", to: path) == nil)
    #expect(try String(contentsOfFile: path, encoding: .utf8) == "report")
  }

  @Test
  func duplicateIdsAreDetected() throws {
    let spec = try #require(Catalog.all.first)
    #expect(SelfTest.duplicateIDs(in: Catalog.all).isEmpty)
    #expect(SelfTest.duplicateIDs(in: Catalog.all + [spec]) == [spec.id])
  }
}

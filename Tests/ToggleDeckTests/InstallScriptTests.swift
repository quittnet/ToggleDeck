import Foundation
import Testing

struct InstallScriptTests {
  private func script() throws -> String {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent("install.sh"), encoding: .utf8)
  }

  /// Lines of code, without comments, so a comment may still name a command.
  private func commands() throws -> [String] {
    try script().split(separator: "\n").map {
      $0.trimmingCharacters(in: .whitespaces)
    }.filter { !$0.hasPrefix("#") }
  }

  @Test
  func testInstallerNeverLoadsTheLoginItemIntoTheCurrentSession() throws {
    // A RunAtLoad job loaded now is started by launchd, outside LaunchServices,
    // so the app opened afterwards runs a second time.
    for line in try commands() {
      #expect(!line.contains("launchctl bootstrap"), Comment(rawValue: line))
      #expect(!line.contains("launchctl load"), Comment(rawValue: line))
      #expect(!line.contains("launchctl kickstart"), Comment(rawValue: line))
    }
  }

  @Test
  func testInstallerStartsTheAppOnceAndStillWritesTheLoginItem() throws {
    let lines = try commands()
    #expect(lines.filter { $0 == "open \"$APP\"" }.count == 1)
    #expect(lines.contains { $0.contains("<key>RunAtLoad</key>") })
    #expect(lines.contains { $0.hasPrefix("cat > \"$PLIST\"") })
  }
}

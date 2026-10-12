import Foundation

/// Uses an existing permission for these exact power commands, without creating
/// or extending a sudo rule. macOS authorization remains the fallback.
enum LowPowerAuthorization {
  private static let commands: Set<String> = [
    "/usr/bin/pmset -a lowpowermode 0",
    "/usr/bin/pmset -a lowpowermode 1",
  ]

  static func run(
    _ command: String, reason: String,
    noninteractive: (String) -> ShellResult = { Shell.run($0, timeout: 20) },
    authorize: (String, String) -> ShellResult = { Shell.runAsAdmin($0, reason: $1) }
  ) -> ShellResult {
    guard commands.contains(command) else { return authorize(command, reason) }

    // -n never asks for a password. The C locale makes sudo's authorization
    // errors recognizable without confusing them with an actual pmset failure.
    let result = noninteractive("LC_ALL=C /usr/bin/sudo -n -- \(command)")
    guard !result.ok else { return result }
    let denied = result.err.split(separator: "\n").contains { line in
      (line.hasPrefix("sudo:") || line.hasPrefix("Sorry, user "))
        && (line.contains("a password is required") || line.contains("not allowed to execute")
          || line.contains("may not run sudo"))
    }
    guard result.status == 1, denied else { return result }
    return authorize(command, reason)
  }
}

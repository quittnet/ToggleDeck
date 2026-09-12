import Darwin
import Foundation

/// Result of a shell invocation.
///
/// `out` is stdout only. `err` is kept separate because the output of several
/// reads is parsed with `hasPrefix`, and a stray warning on stderr — which
/// `system_profiler` and `networksetup` both emit routinely — would otherwise
/// be spliced in front of the value and make the parse fail.
struct ShellResult: Sendable {
  let status: Int32
  let out: String
  var err: String = ""
  var ok: Bool { status == 0 }

  /// stdout, or stderr when the command failed without saying anything on
  /// stdout. For error messages, not for parsing.
  var message: String { out.isEmpty ? err : out }
}

enum Shell {

  /// One monotonic deadline covers the process and both output streams.
  /// Nonblocking reads require no background reader threads. We keep the
  /// shell unreaped until its pipes close, reserving its process-group ID
  /// while descendants might still need termination.
  @discardableResult
  static func run(_ command: String, timeout: TimeInterval = 6) -> ShellResult {
    var outPipe: [Int32] = [-1, -1]
    var errPipe: [Int32] = [-1, -1]
    guard pipe(&outPipe) == 0 else {
      return ShellResult(status: -1, out: "", err: "pipe() failed")
    }
    guard pipe(&errPipe) == 0 else {
      close(outPipe[0])
      close(outPipe[1])
      return ShellResult(status: -1, out: "", err: "pipe() failed")
    }

    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
    posix_spawn_file_actions_adddup2(&actions, outPipe[1], 1)
    posix_spawn_file_actions_adddup2(&actions, errPipe[1], 2)
    for fd in outPipe + errPipe where fd > 2 {
      posix_spawn_file_actions_addclose(&actions, fd)
    }

    var attr: posix_spawnattr_t?
    posix_spawnattr_init(&attr)
    // Unrelated concurrent commands must not inherit one another's pipes.
    posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
    posix_spawnattr_setpgroup(&attr, 0)

    var pid: pid_t = 0
    let arguments: [String] = ["/bin/sh", "-c", command]
    var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) }
    argv.append(nil)
    // Snapshot through Foundation rather than accessing mutable environ.
    var envp = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") }
    envp.append(nil)
    let rc = posix_spawn(&pid, "/bin/sh", &actions, &attr, &argv, &envp)
    for arg in argv { free(arg) }
    for entry in envp { free(entry) }
    posix_spawn_file_actions_destroy(&actions)
    posix_spawnattr_destroy(&attr)
    close(outPipe[1])
    close(errPipe[1])

    var outFD = outPipe[0]
    var errFD = errPipe[0]
    defer {
      if outFD >= 0 { close(outFD) }
      if errFD >= 0 { close(errFD) }
    }
    guard rc == 0 else {
      return ShellResult(status: -1, out: "", err: "spawn failed (\(rc))")
    }
    for fd in [outFD, errFD] {
      let flags = fcntl(fd, F_GETFL)
      guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else {
        terminateAndReap(pid)
        return ShellResult(status: -1, out: "", err: "Could not read command output")
      }
    }

    var out = Data()
    var err = Data()
    var status: Int32 = 0
    let deadline = ProcessInfo.processInfo.systemUptime + max(0, timeout)
    while true {
      guard drain(&outFD, into: &out), drain(&errFD, into: &err) else {
        terminateAndReap(pid)
        return ShellResult(status: -1, out: "", err: "Could not read command output")
      }
      if outFD < 0 && errFD < 0 {
        let result = waitpid(pid, &status, WNOHANG)
        if result == pid { break }
        if result < 0 && errno != EINTR {
          return ShellResult(status: -1, out: "", err: "Could not wait for command")
        }
      }
      if ProcessInfo.processInfo.systemUptime >= deadline {
        terminateAndReap(pid)
        return ShellResult(status: -2, out: "", err: "timed out after \(timeout)s")
      }
      usleep(2_000)
    }
    let exitCode: Int32 = status & 0x7f == 0 ? (status >> 8) & 0xff : -4
    return ShellResult(
      status: exitCode,
      out: String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
      err: String(decoding: err, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
  }

  /// Bound each drain pass so a continuously writing child cannot starve the deadline.
  private static func drain(_ fd: inout Int32, into data: inout Data) -> Bool {
    guard fd >= 0 else { return true }
    var buffer = [UInt8](repeating: 0, count: 16 * 1024)
    for _ in 0..<16 {
      let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
      if count > 0 {
        data.append(contentsOf: buffer.prefix(count))
      } else if count == 0 {
        close(fd)
        fd = -1
        return true
      } else if errno == EAGAIN || errno == EWOULDBLOCK {
        return true
      } else if errno != EINTR {
        return false
      }
    }
    return true
  }

  private static func terminateAndReap(_ pid: pid_t) {
    kill(-pid, SIGKILL)
    var status: Int32 = 0
    while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
  }

  /// Runs a command as root via the system authorization dialog.
  ///
  /// macOS renders the password prompt itself. ToggleDeck never sees, stores,
  /// or transmits the password.
  @discardableResult
  static func runAsAdmin(_ command: String, reason: String) -> ShellResult {
    let escapedCommand = appleScriptEscape(command)
    let escapedReason = appleScriptEscape(reason)
    let script =
      "do shell script \"\(escapedCommand)\" with prompt \"\(escapedReason)\" with administrator privileges"

    // No timeout: the dialog stays up until the user answers it.
    let result = run("/usr/bin/osascript -e \(quote(script))", timeout: 600)

    // -128 is the locale-independent "user cancelled" code. Matching the
    // English message alone would misreport a cancel as a hard failure on a
    // non-English system.
    let combined = result.out + result.err
    if !result.ok && (combined.contains("-128") || combined.contains("User canceled")) {
      return ShellResult(status: -3, out: "", err: "cancelled")
    }
    return result
  }

  /// Escapes a string for embedding inside an AppleScript double-quoted
  /// literal. Newlines are stripped: they would terminate the literal, and no
  /// catalog command legitimately contains one.
  private static func appleScriptEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\r", with: " ")
  }

  /// Quotes an arbitrary string as a single POSIX shell word.
  static func quote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  static func binaryExists(_ path: String) -> Bool {
    FileManager.default.isExecutableFile(atPath: path)
  }

  /// First existing path from a candidate list, e.g. Homebrew's two prefixes.
  static func firstBinary(_ paths: [String]) -> String? {
    paths.first(where: binaryExists)
  }
}

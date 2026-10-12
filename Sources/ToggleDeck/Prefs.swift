import Foundation

/// Reads and writes macOS preference domains.
///
/// Reads go through CFPreferences in-process: this avoids spawning
/// a command for every control during refresh.
/// Writes shell out to `/usr/bin/defaults` because that is the path every
/// system daemon is known to observe, and because root writes have to go
/// through the authorization prompt anyway.
enum Prefs {

  /// `defaults` accepts NSGlobalDomain; CFPreferences wants the real plist name.
  static func cfDomain(_ domain: String) -> String {
    (domain == "NSGlobalDomain" || domain == "-g" || domain == "Apple Global Domain")
      ? ".GlobalPreferences"
      : domain
  }

  // MARK: Reading

  static func read(_ b: DefaultsBacking) -> Any? {
    let domain = cfDomain(b.domain) as CFString
    let key = b.key as CFString

    switch b.scope {
    case .user:
      CFPreferencesAppSynchronize(domain)
      return CFPreferencesCopyAppValue(key, domain)
    case .byHost:
      // Synchronize first, or a verify read 350ms after a write can still
      // see the in-process cached value and report a spurious rejection.
      CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
      return CFPreferencesCopyValue(
        key, domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    case .system:
      CFPreferencesSynchronize(domain, kCFPreferencesAnyUser, kCFPreferencesCurrentHost)
      return CFPreferencesCopyValue(key, domain, kCFPreferencesAnyUser, kCFPreferencesCurrentHost)
    }
  }

  /// Absent override keys resolve to OFF, including after a verified deletion.
  static func readBool(_ b: DefaultsBacking, verifyingWrite: Bool = false) -> Bool? {
    b.value.isOn(read(b), verifyingWrite: verifyingWrite)
  }

  // MARK: Writing

  /// `defaults` uses different absent-key diagnostics across macOS versions.
  static func isMissingKeyError(_ result: ShellResult) -> Bool {
    result.status == 1
      && (result.err.contains("does not exist") || result.err.contains("Could not find key"))
  }

  /// Builds the `defaults write` or `defaults delete` invocation for one backing.
  static func writeCommand(_ b: DefaultsBacking, on: Bool) -> String {
    let prefix: String
    let target: String
    switch b.scope {
    case .user:
      prefix = "/usr/bin/defaults"
      target = b.domain
    case .byHost:
      prefix = "/usr/bin/defaults -currentHost"
      target = b.domain
    case .system:
      prefix = "/usr/bin/defaults"
      target = "/Library/Preferences/\(b.domain)"
    }
    let key = "\(Shell.quote(target)) \(Shell.quote(b.key))"
    guard let literal = b.value.writeLiteral(on: on) else {
      return "\(prefix) delete \(key)"
    }
    return "\(prefix) write \(key) \(literal.flag) \(literal.value)"
  }

  /// True when the domain is TCC-protected and needs Full Disk Access to write,
  /// either because TCC guards the domain itself or because it lives inside
  /// another app's sandbox container.
  static func isProtectedDomain(_ domain: String) -> Bool {
    let protected = [
      "com.apple.universalaccess",
      "com.apple.AdLib",
      "com.apple.TimeMachine",
      // Sandboxed apps — reached by container path.
      "com.apple.Safari",
      "com.apple.TextEdit",
      "com.apple.mail",
      "com.apple.helpviewer",
    ]
    return protected.contains(domain)
  }
}

// MARK: - Small helpers used by the catalog

extension DefaultsBacking {
  static func global(_ key: String, _ value: PrefValue = .boolean, byHost: Bool = false)
    -> DefaultsBacking
  {
    DefaultsBacking(
      domain: "NSGlobalDomain", key: key, value: value, scope: byHost ? .byHost : .user)
  }
}

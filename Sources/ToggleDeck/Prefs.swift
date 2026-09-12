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

  /// Resolved switch position, or nil when the key has never been written.
  static func readBool(_ b: DefaultsBacking) -> Bool? {
    b.value.isOn(read(b))
  }

  // MARK: Writing

  /// Builds the `defaults write` invocation for one backing.
  static func writeCommand(_ b: DefaultsBacking, on: Bool) -> String {
    let lit = b.value.writeLiteral(on: on)
    switch b.scope {
    case .user:
      let target = b.domain
      return
        "/usr/bin/defaults write \(Shell.quote(target)) \(Shell.quote(b.key)) \(lit.flag) \(lit.value)"
    case .byHost:
      return
        "/usr/bin/defaults -currentHost write \(Shell.quote(b.domain)) \(Shell.quote(b.key)) \(lit.flag) \(lit.value)"
    case .system:
      let path = "/Library/Preferences/\(b.domain)"
      return
        "/usr/bin/defaults write \(Shell.quote(path)) \(Shell.quote(b.key)) \(lit.flag) \(lit.value)"
    }
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

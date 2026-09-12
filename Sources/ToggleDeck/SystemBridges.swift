import AppKit
import Foundation

// MARK: - Objective-C shapes for the private brightness clients
//
// CoreBrightness is not a public framework, so the classes are reached through
// the ObjC runtime. Declaring the selectors as `@objc optional` lets Swift emit
// a `respondsToSelector:` check for free, which is what keeps this from
// crashing when Apple renames something in a future macOS.

@objc private protocol BlueLightProbe {
  @objc optional func setEnabled(_ enabled: Bool) -> Bool
  @objc optional func getBlueLightStatus(_ status: UnsafeMutableRawPointer) -> Bool
  @objc optional func setMode(_ mode: Int32) -> Bool
  @objc optional func supported() -> Bool
}

@objc private protocol TrueToneProbe {
  @objc optional func isTrueToneAvailable() -> Bool
  @objc optional func isTrueToneEnabled() -> Bool
  @objc optional func setTrueToneEnabled(_ enabled: Bool) -> Bool
  @objc optional func available() -> Bool
  @objc optional func enabled() -> Bool
  @objc optional func setEnabled(_ enabled: Bool) -> Bool
}

// MARK: - Bridges

/// Toggles that need a real API or a managed child process rather than a
/// preference write.
final class Bridges: @unchecked Sendable {
  static let shared = Bridges()

  /// Guards every mutable field below. Bridges is a process-wide singleton
  /// reached from the main actor (cheap reads), from TaskGroup children
  /// (refreshAll), and from detached write tasks, all of which can overlap —
  /// the 20-second auto-refresh alone can land mid-write.
  private let lock = NSRecursiveLock()

  private init() {
    // Force the dlopen-backed clients now. As `lazy var`s they are not
    // atomic, so a first touch racing between a main-actor read and a
    // detached write could initialise twice or observe a torn pointer.
    _ = ioBluetooth
    _ = blueLightClient
    _ = trueToneClient
  }

  // MARK: Bluetooth

  private lazy var ioBluetooth: UnsafeMutableRawPointer? =
    dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_LAZY)

  private typealias BTGetPower = @convention(c) () -> Int32
  private typealias BTSetPower = @convention(c) (Int32) -> Void

  private var blueutilPath: String? {
    Shell.firstBinary(["/opt/homebrew/bin/blueutil", "/usr/local/bin/blueutil"])
  }

  // IOBluetooth's power-state calls reach CoreBluetooth, and CoreBluetooth
  // does not return an error when TCC is unhappy — it calls abort(). That has
  // been observed on this macOS build even with NSBluetoothAlwaysUsageDescription
  // present in the bundle, so the call is never made in-process. Instead the
  // app re-executes itself with --bt-get / --bt-set: a TCC abort then kills a
  // throwaway child, and the parent sees a non-zero exit and falls back.

  /// Entry point for the child process. Runs the private call directly.
  static func runBluetoothHelper(_ args: [String]) -> Int32 {
    guard let h = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_LAZY)
    else { return 2 }

    if args.contains("--bt-get") {
      guard let sym = dlsym(h, "IOBluetoothPreferenceGetControllerPowerState") else { return 2 }
      let get = unsafeBitCast(sym, to: BTGetPower.self)
      print(get() != 0 ? "1" : "0")
      return 0
    }

    guard let idx = args.firstIndex(of: "--bt-set"), idx + 1 < args.count,
      let sym = dlsym(h, "IOBluetoothPreferenceSetControllerPowerState")
    else { return 2 }
    let set = unsafeBitCast(sym, to: BTSetPower.self)
    set(args[idx + 1] == "1" ? 1 : 0)
    // Give the daemon a moment to apply before the process exits.
    usleep(500_000)
    return 0
  }

  private var selfExecutable: String? {
    Bundle.main.executablePath ?? CommandLine.arguments.first
  }

  private func helper(_ arguments: String) -> ShellResult? {
    guard let exe = selfExecutable else { return nil }
    return Shell.run("\(Shell.quote(exe)) \(arguments)", timeout: 8)
  }

  /// Set by the last read. Reported by `bluetoothSupported()` so a refresh
  /// never costs an extra probe.
  private var bluetoothProbe: Bool?

  private func setBluetoothProbe(_ value: Bool) {
    lock.lock()
    bluetoothProbe = value
    lock.unlock()
  }

  func bluetoothSupported() -> Bool {
    lock.lock()
    let cached = bluetoothProbe
    lock.unlock()
    if let cached { return cached }
    return bluetoothIsOn() != nil
  }

  /// Reads through system_profiler rather than IOBluetooth. The private call
  /// spends ~3.5s bringing up the CoreBluetooth coordinator and drags TCC into
  /// the read path; this costs ~150ms and neither.
  func bluetoothIsOn() -> Bool? {
    let r = Shell.run(
      "/usr/sbin/system_profiler SPBluetoothDataType 2>/dev/null | /usr/bin/awk -F': *' '/State:/{print $2; exit}'",
      timeout: 8)
    if r.ok {
      let s = r.out.lowercased()
      if s.hasPrefix("on") {
        setBluetoothProbe(true)
        return true
      }
      if s.hasPrefix("off") {
        setBluetoothProbe(true)
        return false
      }
    }
    if let bu = blueutilPath {
      let b = Shell.run("\(Shell.quote(bu)) -p", timeout: 4)
      if b.ok {
        setBluetoothProbe(true)
        return b.out.hasPrefix("1")
      }
    }
    setBluetoothProbe(false)
    return nil
  }

  /// Returns nil on success, or a human-readable reason on failure.
  func setBluetooth(_ on: Bool) -> String? {
    if let r = helper("--bt-set \(on ? 1 : 0)"), r.ok {
      usleep(300_000)
      if bluetoothIsOn() == on { return nil }
    }
    if let bu = blueutilPath {
      let r = Shell.run("\(Shell.quote(bu)) -p \(on ? 1 : 0)", timeout: 6)
      if r.ok {
        usleep(300_000)
        if bluetoothIsOn() == on { return nil }
      }
    }
    return
      "macOS blocked the Bluetooth change. Run 'brew install blueutil' for a fallback that does not depend on private APIs."
  }

  // MARK: Night Shift

  private lazy var coreBrightness: UnsafeMutableRawPointer? =
    dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)

  private lazy var blueLightClient: BlueLightProbe? = {
    _ = coreBrightness
    guard let cls = NSClassFromString("CBBlueLightClient") as? NSObject.Type else { return nil }
    return unsafeBitCast(cls.init(), to: BlueLightProbe.self)
  }()

  func nightShiftSupported() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard let c = blueLightClient else { return false }
    return c.supported?() ?? true
  }

  /// Offset of the `enabled` flag inside CBBlueLightClient's private status
  /// struct.
  ///
  /// The struct is undocumented, but the ObjC type encoding of
  /// `getBlueLightStatus:` spells its layout exactly:
  ///
  ///     ^{?=BBBi{?={?=ii}{?=ii}}QB}
  ///      │  │││ └ int mode, Schedule{Time from; Time to}, uint64 flags, BOOL available
  ///      │  ││└ sunSchedulePermitted
  ///      │  │└ enabled          <- offset 1
  ///      │  └ active            <- offset 0
  ///
  /// Confirmed against the live framework: writing setEnabled: moves byte 1
  /// and never moves byte 0, which stays 1 regardless of state. Reading byte 0
  /// is what made every "turn Night Shift off" report failure.
  ///
  /// The value is still stored rather than hardcoded so that a future macOS
  /// reordering the struct self-corrects on the next write.
  private static let defaultNightShiftOffset = 1

  private var nightShiftOffset: Int {
    get {
      let v = UserDefaults.standard.object(forKey: "nightShiftEnabledOffset") as? Int
      // Anything outside the three leading BOOLs is a stale value from an
      // earlier build; fall back rather than trust it.
      guard let v, (0...2).contains(v) else { return Self.defaultNightShiftOffset }
      return v
    }
    set { UserDefaults.standard.set(newValue, forKey: "nightShiftEnabledOffset") }
  }

  private func blueLightStatusBytes() -> [UInt8]? {
    guard let client = blueLightClient else { return nil }
    // The struct measures 40 bytes today. Over-allocating well past that is
    // cheap insurance: if a future macOS grows it, a snug buffer would be a
    // heap overwrite rather than a wrong reading.
    let size = 256
    let buf = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
    defer { buf.deallocate() }
    buf.initializeMemory(as: UInt8.self, repeating: 0, count: size)
    guard client.getBlueLightStatus?(buf) == true else { return nil }
    let p = buf.assumingMemoryBound(to: UInt8.self)
    return (0..<size).map { p[$0] }
  }

  func nightShiftIsOn() -> Bool? {
    lock.lock()
    defer { lock.unlock() }
    guard let bytes = blueLightStatusBytes() else { return nil }
    return bytes[nightShiftOffset] != 0
  }

  func setNightShift(_ on: Bool) -> String? {
    // Only the write needs the lock held across it. The settle delay below does
    // not, and a refresh reads Night Shift through this same lock from the main
    // actor, so sleeping inside it stalled the UI thread for 250ms.
    lock.lock()
    guard let client = blueLightClient else {
      lock.unlock()
      return "Night Shift is not available on this Mac."
    }
    let before = blueLightStatusBytes()

    // Deliberately no setMode() call. Mode is the user's schedule choice
    // (off / custom hours / sunset to sunrise); forcing it to 0 to make the
    // switch authoritative would silently discard a schedule they set in
    // System Settings. setEnabled alone turns Night Shift on and off.
    let accepted = client.setEnabled?(on) == true
    lock.unlock()
    guard accepted else { return "Night Shift rejected the change." }

    usleep(250_000)

    lock.lock()
    defer { lock.unlock() }

    // Recalibrate against reality: the field that *changed* and now equals
    // what we wrote is `enabled`. The previous condition tested
    // `before != want` instead of `before != after`, which can hold for a
    // byte that never moved, so a constant field could never be ruled out.
    if let before, let after = blueLightStatusBytes() {
      let want: UInt8 = on ? 1 : 0
      for candidate in 0...2 where after[candidate] == want && before[candidate] != after[candidate]
      {
        nightShiftOffset = candidate
        break
      }
    }
    return nil
  }

  // MARK: True Tone

  private lazy var trueToneClient: TrueToneProbe? = {
    _ = coreBrightness
    guard let cls = NSClassFromString("CBTrueToneClient") as? NSObject.Type else { return nil }
    return unsafeBitCast(cls.init(), to: TrueToneProbe.self)
  }()

  func trueToneSupported() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard let c = trueToneClient else { return false }
    if let a = c.isTrueToneAvailable?() { return a }
    if let a = c.available?() { return a }
    return false
  }

  func trueToneIsOn() -> Bool? {
    lock.lock()
    defer { lock.unlock() }
    guard let c = trueToneClient else { return nil }
    if let e = c.isTrueToneEnabled?() { return e }
    if let e = c.enabled?() { return e }
    return nil
  }

  func setTrueTone(_ on: Bool) -> String? {
    lock.lock()
    defer { lock.unlock() }
    guard let c = trueToneClient else { return "True Tone is not available on this display." }
    if c.setTrueToneEnabled?(on) == true { return nil }
    if c.setEnabled?(on) == true { return nil }
    return "True Tone rejected the change."
  }

  // MARK: Dark Mode

  func darkModeIsOn() -> Bool {
    let raw =
      CFPreferencesCopyAppValue(
        "AppleInterfaceStyle" as CFString,
        ".GlobalPreferences" as CFString) as? String
    return raw?.caseInsensitiveCompare("Dark") == .orderedSame
  }

  func setDarkMode(_ on: Bool) -> String? {
    let script =
      "tell application \"System Events\" to tell appearance preferences to set dark mode to \(on)"
    let r = Shell.run("/usr/bin/osascript -e \(Shell.quote(script))", timeout: 10)
    if r.ok { return nil }
    let message = r.message
    if message.contains("-1743") || message.lowercased().contains("not allowed") {
      return
        "Grant ToggleDeck permission to control System Events under Privacy & Security → Automation."
    }
    return message.isEmpty ? "Appearance change failed." : message
  }

  // MARK: Keep Awake

  private let keepAwake = KeepAwakeController()

  func caffeinateIsOn() -> Bool { keepAwake.isOn }
  func setCaffeinate(_ on: Bool) -> String? { keepAwake.set(on) }
  func shutdown() { _ = keepAwake.set(false) }

  // MARK: Dispatch

  func supported(_ bridge: Bridge) -> Bool {
    switch bridge {
    case .bluetooth: return bluetoothSupported()
    case .nightShift: return nightShiftSupported()
    case .trueTone: return trueToneSupported()
    case .caffeinate: return true
    case .darkMode: return true
    }
  }

  func read(_ bridge: Bridge) -> Bool? {
    switch bridge {
    case .bluetooth: return bluetoothIsOn()
    case .nightShift: return nightShiftIsOn()
    case .trueTone: return trueToneIsOn()
    case .caffeinate: return caffeinateIsOn()
    case .darkMode: return darkModeIsOn()
    }
  }

  func write(_ bridge: Bridge, on: Bool) -> String? {
    switch bridge {
    case .bluetooth: return setBluetooth(on)
    case .nightShift: return setNightShift(on)
    case .trueTone: return setTrueTone(on)
    case .caffeinate: return setCaffeinate(on)
    case .darkMode: return setDarkMode(on)
    }
  }
}

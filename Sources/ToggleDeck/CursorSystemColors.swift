import AppKit
import CoreFoundation
import Darwin

/// The same cursor preference and refresh functions used by Accessibility settings.
/// These are system SPI, so every symbol is resolved before changing anything.
enum CursorSystemColors {
  private static var domain: CFString { "com.apple.universalaccess" as CFString }
  private static let lock = NSRecursiveLock()
  private static let api = API()

  static func read() -> CursorColors? {
    lock.lock()
    defer { lock.unlock() }
    _ = CFPreferencesAppSynchronize(domain)
    return currentColors()
  }

  /// Returns a recovery message on failure. The app never requests administrator access.
  static func write(_ colors: CursorColors) -> String? {
    lock.lock()
    defer { lock.unlock() }
    guard colors.fill.isValid, colors.outline.isValid else {
      return "Choose valid cursor colors."
    }
    guard let api, api.canWrite else {
      return
        "ToggleDeck cannot apply cursor colors on this macOS version. Open Pointer Settings to change them."
    }
    _ = CFPreferencesAppSynchronize(domain)
    guard let previous = currentColors() else {
      return
        "The current cursor colors could not be read. Open Accessibility Display settings and try again."
    }
    apply(colors, using: api)
    guard CFPreferencesAppSynchronize(domain),
      let actual = currentColors(), matches(actual, colors)
    else {
      // Failed preference synchronization can leave an optimistic value in the cache.
      // Restore the original values before another synchronization or refresh occurs.
      apply(previous, using: api)
      _ = CFPreferencesAppSynchronize(domain)
      refresh(using: api)
      return
        "macOS could not save the cursor colors. Enable Full Disk Access for ToggleDeck in Privacy & Security. If it is already enabled, remove and re-add the current ToggleDeck app. Then quit and reopen ToggleDeck. You can also change colors in Pointer Settings."
    }
    refresh(using: api)
    return nil
  }

  private static func apply(_ colors: CursorColors, using api: API) {
    let fill = colors.fill.nsColor.cgColor
    let outline = colors.outline.nsColor.cgColor
    // Apple's settings pane changes the customization flag before the colors.
    withExtendedLifetime((fill, outline)) {
      api.setCustomized?(colors.customized ? 1 : 0)
      api.setFill?(Unmanaged.passUnretained(fill).toOpaque())
      api.setOutline?(Unmanaged.passUnretained(outline).toOpaque())
    }
  }

  private static func refresh(using api: API) {
    // Re-registering the system cursor images makes the change visible immediately.
    // Unregister first to replace cached custom cursor images as well as reset them.
    api.unregister?()
    if api.isCustomized() != 0 { _ = api.register?() }
    if let notification = api.notification {
      CFNotificationCenterPostNotification(
        CFNotificationCenterGetDistributedCenter(),
        CFNotificationName(notification), nil, nil, true)
    }
  }

  private static func currentColors() -> CursorColors? {
    if let api {
      guard api.isCustomized() != 0 else { return .standard }
      guard let fill = copiedColor(api.copyFill, key: "cursorFill", fallback: .black),
        let outline = copiedColor(api.copyOutline, key: "cursorOutline", fallback: .white)
      else { return nil }
      return CursorColors(fill: fill, outline: outline, customized: true)
    }
    let flag = CFPreferencesCopyAppValue("cursorIsCustomized" as CFString, domain)
    if flag == nil { return .standard }
    guard let customized = flag as? NSNumber else { return nil }
    guard customized.boolValue else { return .standard }
    guard let fill = preferenceColor("cursorFill", fallback: .black),
      let outline = preferenceColor("cursorOutline", fallback: .white)
    else { return nil }
    return CursorColors(fill: fill, outline: outline, customized: true)
  }

  private static func copiedColor(
    _ copy: API.CopyColor, key: String, fallback: CursorRGB
  ) -> CursorRGB? {
    guard let pointer = copy() else { return preferenceColor(key, fallback: fallback) }
    let value = Unmanaged<CGColor>.fromOpaque(pointer).takeRetainedValue()
    guard let color = NSColor(cgColor: value)?.usingColorSpace(.sRGB) else { return nil }
    let result = CursorRGB(
      red: color.redComponent, green: color.greenComponent,
      blue: color.blueComponent, alpha: color.alphaComponent)
    return result.isValid ? result : nil
  }

  private static func preferenceColor(_ key: String, fallback: CursorRGB) -> CursorRGB? {
    guard let value = CFPreferencesCopyAppValue(key as CFString, domain) else { return fallback }
    guard let dictionary = value as? [String: Any] else { return nil }
    return CursorRGB(components: dictionary)
  }

  private static func matches(_ actual: CursorColors, _ requested: CursorColors) -> Bool {
    func close(_ lhs: CursorRGB, _ rhs: CursorRGB) -> Bool {
      zip(
        [lhs.red, lhs.green, lhs.blue, lhs.alpha],
        [rhs.red, rhs.green, rhs.blue, rhs.alpha]
      ).allSatisfy { abs($0 - $1) < 0.000_01 }
    }
    return actual.customized == requested.customized
      && close(actual.fill, requested.fill) && close(actual.outline, requested.outline)
  }

  private final class API: @unchecked Sendable {
    typealias CopyColor = @convention(c) () -> UnsafeRawPointer?
    typealias SetColor = @convention(c) (UnsafeRawPointer?) -> Void
    typealias GetCustomized = @convention(c) () -> UInt8
    typealias SetCustomized = @convention(c) (UInt8) -> Void
    typealias Unregister = @convention(c) () -> Void
    typealias Register = @convention(c) () -> UInt8

    let copyFill: CopyColor
    let copyOutline: CopyColor
    let isCustomized: GetCustomized
    let setFill: SetColor?
    let setOutline: SetColor?
    let setCustomized: SetCustomized?
    let unregister: Unregister?
    let register: Register?
    let notification: CFString?

    var canWrite: Bool {
      setFill != nil && setOutline != nil && setCustomized != nil
        && unregister != nil && register != nil && notification != nil
    }

    init?() {
      guard
        let services = dlopen(
          "/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/HIServices",
          RTLD_LAZY | RTLD_LOCAL),
        let fill = dlsym(services, "_AXInterfaceCopyCursorColorFill"),
        let outline = dlsym(services, "_AXInterfaceCopyCursorColorOutline"),
        let customized = dlsym(services, "_AXInterfaceCursorIsOverridden")
      else { return nil }
      copyFill = unsafeBitCast(fill, to: CopyColor.self)
      copyOutline = unsafeBitCast(outline, to: CopyColor.self)
      isCustomized = unsafeBitCast(customized, to: GetCustomized.self)
      setFill = dlsym(services, "_AXInterfaceSetCursorColorFill").map {
        unsafeBitCast($0, to: SetColor.self)
      }
      setOutline = dlsym(services, "_AXInterfaceSetCursorColorOutline").map {
        unsafeBitCast($0, to: SetColor.self)
      }
      setCustomized = dlsym(services, "_AXInterfaceSetCursorIsOverridden").map {
        unsafeBitCast($0, to: SetCustomized.self)
      }
      notification = dlsym(services, "kAXInterfaceCursorStatusDidChangeNotification").map {
        $0.assumingMemoryBound(to: CFString.self).pointee
      }
      let support = dlopen(
        "/System/Library/PrivateFrameworks/AccessibilitySupport.framework/Versions/A/AccessibilitySupport",
        RTLD_LAZY | RTLD_LOCAL)
      unregister = support.flatMap { dlsym($0, "AXFCursorUnregisterAll") }.map {
        unsafeBitCast($0, to: Unregister.self)
      }
      register = support.flatMap { dlsym($0, "AXFCursorRegisterAll") }.map {
        unsafeBitCast($0, to: Register.self)
      }
      // Framework handles remain loaded for the lifetime of these function pointers.
    }
  }
}

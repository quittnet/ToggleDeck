import Foundation

/// The version of the installed bundle, read from its Info.plist.
///
/// `install.sh` is the only place the version is written. A binary run outside
/// the app bundle has no Info.plist, so it reports itself as a development
/// build instead of repeating a number that may not match its sources.
enum AppVersion {
  static var short: String? {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
  }

  static var build: String? {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
  }

  /// "2.7.1 (16)", "2.7.1", or "development build".
  static var display: String { describe(short: short, build: build) }

  static func describe(short: String?, build: String?) -> String {
    guard let short, !short.isEmpty else { return "development build" }
    guard let build, !build.isEmpty else { return short }
    return "\(short) (\(build))"
  }
}

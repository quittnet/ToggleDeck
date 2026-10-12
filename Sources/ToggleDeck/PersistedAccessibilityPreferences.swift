import CoreFoundation
import Foundation

struct PersistedAccessibilityPreferences {
  enum Domain {
    case universalAccess
    case global

    func fileURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
      let filename =
        switch self {
        case .universalAccess: "com.apple.universalaccess.plist"
        case .global: ".GlobalPreferences.plist"
        }
      return home.appendingPathComponent("Library/Preferences", isDirectory: true)
        .appendingPathComponent(filename, isDirectory: false)
    }
  }

  enum ParseError: Error, Equatable {
    case dictionaryRequired
  }

  private let values: [String: Any]

  init(data: Data) throws {
    let propertyList = try PropertyListSerialization.propertyList(
      from: data, options: [], format: nil)
    guard let values = propertyList as? [String: Any] else {
      throw ParseError.dictionaryRequired
    }
    self.values = values
  }

  private init(values: [String: Any]) {
    self.values = values
  }

  static func load(
    domain: Domain,
    home: URL = FileManager.default.homeDirectoryForCurrentUser,
    readData: (URL) throws -> Data = { try Data(contentsOf: $0) }
  ) throws -> PersistedAccessibilityPreferences {
    let data: Data
    do {
      data = try readData(domain.fileURL(home: home))
    } catch let error as NSError
      where error.domain == NSCocoaErrorDomain
      && (error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError)
    {
      return PersistedAccessibilityPreferences(values: [:])
    }
    return try PersistedAccessibilityPreferences(data: data)
  }

  func scaleMatches(_ expected: Double) -> Bool {
    guard expected.isFinite, (1...4).contains(expected) else { return false }
    guard let value = values["mouseDriverCursorSize"] else {
      return abs(expected - 1) <= 0.0001
    }
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
      return false
    }
    let actual = number.doubleValue
    return actual.isFinite && (1...4).contains(actual) && abs(actual - expected) <= 0.0001
  }

  func booleanMatches(key: String, expected: Bool, default defaultValue: Bool) -> Bool {
    guard let value = values[key] else { return expected == defaultValue }
    guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
      return false
    }
    return number.boolValue == expected
  }
}

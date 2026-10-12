import Foundation
import Testing

@testable import ToggleDeck

struct PersistedAccessibilityPreferencesTests {
  private let scaleKey = "mouseDriverCursorSize"
  private let booleanKey = "CGDisableCursorLocationMagnification"
  private let home = URL(fileURLWithPath: "/synthetic/user", isDirectory: true)

  @Test
  func domainPathsUseTheSuppliedHome() {
    #expect(
      PersistedAccessibilityPreferences.Domain.universalAccess.fileURL(home: home).path
        == "/synthetic/user/Library/Preferences/com.apple.universalaccess.plist")
    #expect(
      PersistedAccessibilityPreferences.Domain.global.fileURL(home: home).path
        == "/synthetic/user/Library/Preferences/.GlobalPreferences.plist")
  }

  @Test
  func binaryAndXMLPreferencesPreserveTheirTypes() throws {
    for format in [PropertyListSerialization.PropertyListFormat.binary, .xml] {
      let data = try plist(
        [scaleKey: 1.5, booleanKey: false, "UnrelatedSetting": ["one", "two"]], format: format)
      let preferences = try PersistedAccessibilityPreferences(data: data)
      #expect(preferences.scaleMatches(1.5))
      #expect(!preferences.scaleMatches(1))
      #expect(preferences.booleanMatches(key: booleanKey, expected: false, default: true))
      #expect(!preferences.booleanMatches(key: booleanKey, expected: true, default: true))
    }
  }

  @Test
  func absentScaleCannotConfirmAnOptimisticCachedWrite() throws {
    let preferences = try PersistedAccessibilityPreferences(data: plist([:]))
    #expect(preferences.scaleMatches(1))
    #expect(!preferences.scaleMatches(1.5))
    #expect(!preferences.scaleMatches(4))
  }

  @Test
  func numericScaleSupportsBoundariesAndNativeFloatPrecision() throws {
    for scale in [1.0, 1.25, 1.5, 2, 3, 4] {
      let preferences = try PersistedAccessibilityPreferences(data: plist([scaleKey: scale]))
      #expect(preferences.scaleMatches(scale))
    }
    let preferences = try PersistedAccessibilityPreferences(
      data: plist([scaleKey: Double(Float(1.7))]))
    #expect(preferences.scaleMatches(1.7))
    #expect(!preferences.scaleMatches(1.701))
  }

  @Test
  func invalidExpectedScalesNeverMatch() throws {
    let preferences = try PersistedAccessibilityPreferences(data: plist([scaleKey: 1]))
    for expected in [Double.nan, .infinity, -.infinity, 0.999, 4.001] {
      #expect(!preferences.scaleMatches(expected))
    }
  }

  @Test
  func malformedStoredScalesNeverMatch() throws {
    let values: [Any] = [
      true, false, "1.5", Data([1]), ["scale": 1.5], [1.5], Date(timeIntervalSince1970: 0),
      Double.nan, Double.infinity, -Double.infinity, 0.999, 4.001,
    ]
    for value in values {
      let preferences = try PersistedAccessibilityPreferences(data: plist([scaleKey: value]))
      #expect(!preferences.scaleMatches(1))
      #expect(!preferences.scaleMatches(1.5))
    }
  }

  @Test
  func absentBooleansUseOnlyTheSpecifiedDefault() throws {
    let preferences = try PersistedAccessibilityPreferences(data: plist([:]))
    for defaultValue in [false, true] {
      #expect(
        preferences.booleanMatches(key: booleanKey, expected: defaultValue, default: defaultValue))
      #expect(
        !preferences.booleanMatches(key: booleanKey, expected: !defaultValue, default: defaultValue)
      )
    }
  }

  @Test
  func booleanVerificationRejectsNumericAndStringCoercion() throws {
    for stored in [false, true] {
      let preferences = try PersistedAccessibilityPreferences(data: plist([booleanKey: stored]))
      #expect(preferences.booleanMatches(key: booleanKey, expected: stored, default: !stored))
      #expect(!preferences.booleanMatches(key: booleanKey, expected: !stored, default: !stored))
    }
    let invalidValues: [Any] = [0, 1, 0.0, 1.0, "true", "false", "1", Data(), [true]]
    for value in invalidValues {
      let preferences = try PersistedAccessibilityPreferences(data: plist([booleanKey: value]))
      #expect(!preferences.booleanMatches(key: booleanKey, expected: false, default: false))
      #expect(!preferences.booleanMatches(key: booleanKey, expected: true, default: true))
    }
  }

  @Test
  func malformedDataAndNonDictionaryRootsThrow() throws {
    for data in [Data(), Data("not a property list".utf8), Data("<plist><dict>".utf8)] {
      #expect(throws: (any Error).self) { try PersistedAccessibilityPreferences(data: data) }
    }
    for root in [[1, 2], "text", true] as [Any] {
      let data = try PropertyListSerialization.data(
        fromPropertyList: root, format: .binary, options: 0)
      #expect(throws: PersistedAccessibilityPreferences.ParseError.dictionaryRequired) {
        try PersistedAccessibilityPreferences(data: data)
      }
    }
  }

  @Test
  func genuineCocoaMissingFileErrorsProduceDefaultPreferences() throws {
    for code in [NSFileReadNoSuchFileError, NSFileNoSuchFileError] {
      let preferences = try PersistedAccessibilityPreferences.load(
        domain: .universalAccess, home: home,
        readData: { url in
          #expect(url.path == "/synthetic/user/Library/Preferences/com.apple.universalaccess.plist")
          throw NSError(domain: NSCocoaErrorDomain, code: code)
        })
      #expect(preferences.scaleMatches(1))
      #expect(!preferences.scaleMatches(1.5))
      #expect(preferences.booleanMatches(key: booleanKey, expected: true, default: true))
    }
  }

  @Test
  func deniedAndUnrelatedReadErrorsAreNotTreatedAsMissingFiles() {
    let errors = [
      NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError),
      NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError),
      NSError(domain: NSPOSIXErrorDomain, code: 2),
      NSError(domain: "SyntheticReadError", code: NSFileReadNoSuchFileError),
    ]
    for expected in errors {
      do {
        _ = try PersistedAccessibilityPreferences.load(
          domain: .global, home: home, readData: { _ in throw expected })
        Issue.record("An inaccessible or invalid preference file was treated as absent")
      } catch let actual as NSError {
        #expect(actual.domain == expected.domain && actual.code == expected.code)
      }
    }
  }

  @Test
  func aPresentMalformedFileIsNeverConvertedToDefaults() {
    #expect(throws: (any Error).self) {
      try PersistedAccessibilityPreferences.load(
        domain: .global, home: home, readData: { _ in Data("invalid plist".utf8) })
    }
  }

  @Test
  func everyLoadReadsANewSnapshotRatherThanAProcessCache() throws {
    var diskData = try plist([:])
    var reads = 0
    let readData: (URL) throws -> Data = { _ in
      reads += 1
      return diskData
    }
    let before = try PersistedAccessibilityPreferences.load(
      domain: .universalAccess, home: home, readData: readData)
    diskData = try plist([scaleKey: 1.5])
    let after = try PersistedAccessibilityPreferences.load(
      domain: .universalAccess, home: home, readData: readData)
    #expect(reads == 2)
    #expect(before.scaleMatches(1) && !before.scaleMatches(1.5))
    #expect(after.scaleMatches(1.5) && !after.scaleMatches(1))
  }

  private func plist(
    _ values: [String: Any], format: PropertyListSerialization.PropertyListFormat = .binary
  ) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: values, format: format, options: 0)
  }
}

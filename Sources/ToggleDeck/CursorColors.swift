import AppKit

struct CursorRGB: Equatable, Sendable {
  let red: Double
  let green: Double
  let blue: Double
  let alpha: Double

  init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }

  init?(components: [String: Any]) {
    func number(_ key: String) -> Double? {
      guard let value = components[key] else { return nil }
      if let value = value as? NSNumber {
        guard CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        return value.doubleValue
      }
      return (value as? String).flatMap(Double.init)
    }
    guard let red = number("red"), let green = number("green"), let blue = number("blue"),
      let alpha = number("alpha")
    else { return nil }
    self.init(red: red, green: green, blue: blue, alpha: alpha)
    guard isValid else { return nil }
  }

  init?(_ color: NSColor) {
    guard let value = color.usingColorSpace(.sRGB) else { return nil }
    self.init(
      red: value.redComponent, green: value.greenComponent, blue: value.blueComponent,
      alpha: value.alphaComponent)
    guard isValid else { return nil }
  }

  static let black = CursorRGB(red: 0, green: 0, blue: 0)
  static let white = CursorRGB(red: 1, green: 1, blue: 1)

  var isValid: Bool {
    [red, green, blue, alpha].allSatisfy { $0.isFinite && (0...1).contains($0) }
  }
  var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }

  func matches(_ other: CursorRGB, tolerance: Double = 0.0001) -> Bool {
    zip([red, green, blue, alpha], [other.red, other.green, other.blue, other.alpha])
      .allSatisfy { abs($0 - $1) <= tolerance }
  }
}

struct CursorColors: Equatable, Sendable {
  let fill: CursorRGB
  let outline: CursorRGB
  let customized: Bool

  static let standard = CursorColors(fill: .black, outline: .white, customized: false)
  var isValid: Bool { fill.isValid && outline.isValid }

  func matches(_ other: CursorColors) -> Bool {
    fill.matches(other.fill) && outline.matches(other.outline)
  }
}

enum CursorPreset: String, CaseIterable, Identifiable, Sendable {
  case standard = "Default"
  case white = "White"
  case red = "Red"
  case orange = "Orange"
  case yellow = "Yellow"
  case green = "Green"
  case blue = "Blue"
  case purple = "Purple"
  case pink = "Pink"
  case fire = "Fire"
  case ocean = "Ocean"
  case mint = "Mint"
  case royal = "Royal"
  case candy = "Candy"

  static let solidPresets = allCases.filter { !$0.isCombination }
  static let combinationPresets = allCases.filter(\.isCombination)

  var id: String { rawValue }
  var isCombination: Bool {
    switch self {
    case .fire, .ocean, .mint, .royal, .candy: return true
    default: return false
    }
  }

  var colors: CursorColors {
    let fill: CursorRGB
    let outline: CursorRGB
    switch self {
    case .standard: return .standard
    case .white:
      fill = .white
      outline = .black
    case .red:
      fill = CursorRGB(red: 0.95, green: 0.18, blue: 0.22)
      outline = .white
    case .orange:
      fill = CursorRGB(red: 1, green: 0.55, blue: 0.12)
      outline = .black
    case .yellow:
      fill = CursorRGB(red: 1, green: 0.86, blue: 0.1)
      outline = .black
    case .green:
      fill = CursorRGB(red: 0.22, green: 0.78, blue: 0.37)
      outline = .black
    case .blue:
      fill = CursorRGB(red: 0.08, green: 0.42, blue: 0.95)
      outline = .white
    case .purple:
      fill = CursorRGB(red: 0.62, green: 0.31, blue: 0.88)
      outline = .white
    case .pink:
      fill = CursorRGB(red: 1, green: 0.42, blue: 0.67)
      outline = .black
    case .fire:
      fill = CursorRGB(red: 0.75, green: 0.07, blue: 0.11)
      outline = CursorRGB(red: 1, green: 0.87, blue: 0.15)
    case .ocean:
      fill = CursorRGB(red: 0.03, green: 0.23, blue: 0.6)
      outline = CursorRGB(red: 0.62, green: 0.95, blue: 1)
    case .mint:
      fill = CursorRGB(red: 0.33, green: 0.91, blue: 0.7)
      outline = CursorRGB(red: 0.02, green: 0.2, blue: 0.18)
    case .royal:
      fill = CursorRGB(red: 0.36, green: 0.12, blue: 0.68)
      outline = CursorRGB(red: 1, green: 0.8, blue: 0.22)
    case .candy:
      fill = CursorRGB(red: 1, green: 0.4, blue: 0.68)
      outline = CursorRGB(red: 0.19, green: 0.03, blue: 0.16)
    }
    return CursorColors(fill: fill, outline: outline, customized: true)
  }

  static func matching(_ colors: CursorColors) -> CursorPreset? {
    allCases.first { $0.colors.matches(colors) }
  }

  static func matchesSearch(_ query: String) -> Bool {
    SettingSearch.matches(
      "Cursor Color pointer mouse fill outline custom size scale shake locate "
        + allCases.map(\.rawValue).joined(separator: " "),
      query: query)
  }
}

import Combine
import Foundation

struct SavedCursorPalette: Identifiable, Equatable, Sendable {
  let id: String
  let name: String
  let colors: CursorColors
}

/// Saved combinations belong to ToggleDeck. Saving never applies system colors.
@MainActor
final class CursorPaletteStore: ObservableObject {
  static let shared = CursorPaletteStore()
  static let storageKey = "savedCursorPalettes.v1"

  @Published private(set) var savedColors: [SavedCursorPalette]
  private let store: UserDefaults?

  init(store: UserDefaults? = UserDefaults.standard) {
    self.store = store
    savedColors = Self.load(store?.data(forKey: Self.storageKey))
  }

  static func preview() -> CursorPaletteStore { CursorPaletteStore(store: nil) }

  /// Re-saving the same combination keeps its ID and existing name. An explicit
  /// name renames that entry. Its original exact RGBA values remain unchanged.
  @discardableResult
  func save(_ colors: CursorColors, name: String? = nil) -> SavedCursorPalette? {
    guard colors.isValid else { return nil }
    let requestedName = Self.cleanedName(name)
    if let index = savedColors.firstIndex(where: { Self.matches($0.colors, colors) }) {
      let previous = savedColors[index]
      let updated = SavedCursorPalette(
        id: previous.id, name: requestedName ?? previous.name, colors: previous.colors)
      savedColors[index] = updated
      persist()
      return updated
    }
    let entry = SavedCursorPalette(
      id: UUID().uuidString, name: requestedName ?? Self.defaultName(for: colors), colors: colors)
    savedColors.append(entry)
    persist()
    return entry
  }

  func remove(_ id: String) {
    guard savedColors.contains(where: { $0.id == id }) else { return }
    savedColors.removeAll { $0.id == id }
    persist()
  }

  func matching(_ colors: CursorColors) -> SavedCursorPalette? {
    guard colors.isValid else { return nil }
    return savedColors.first { Self.matches($0.colors, colors) }
  }

  private static func matches(_ lhs: CursorColors, _ rhs: CursorColors) -> Bool {
    lhs.customized == rhs.customized && lhs.matches(rhs)
  }

  private func persist() {
    guard let store,
      let data = try? JSONEncoder().encode(savedColors.map(PersistedPalette.init))
    else { return }
    store.set(data, forKey: Self.storageKey)
  }

  private static func load(_ data: Data?) -> [SavedCursorPalette] {
    guard let data,
      let records = try? JSONDecoder().decode([DecodedPalette].self, from: data)
    else { return [] }
    var result: [SavedCursorPalette] = []
    var ids = Set<String>()
    for record in records {
      guard let record = record.value, UUID(uuidString: record.id) != nil,
        let name = cleanedName(record.name), let colors = record.colors,
        !ids.contains(record.id), !result.contains(where: { matches($0.colors, colors) })
      else { continue }
      ids.insert(record.id)
      result.append(SavedCursorPalette(id: record.id, name: name, colors: colors))
    }
    return result
  }

  private static func cleanedName(_ name: String?) -> String? {
    guard let name else { return nil }
    let cleaned = name.components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }.joined(separator: " ")
    return cleaned.isEmpty ? nil : String(cleaned.prefix(80))
  }

  private static func defaultName(for colors: CursorColors) -> String {
    guard colors.customized else { return "Default" }
    return "\(colorName(colors.fill)) & \(colorName(colors.outline))"
  }

  private static func colorName(_ color: CursorRGB) -> String {
    let choices: [(String, CursorRGB)] =
      [("Black", .black)]
      + CursorPreset.solidPresets.filter { $0 != .standard }.map { ($0.rawValue, $0.colors.fill) }
    func distance(_ candidate: CursorRGB) -> Double {
      pow(color.red - candidate.red, 2) + pow(color.green - candidate.green, 2)
        + pow(color.blue - candidate.blue, 2)
    }
    return choices.min { distance($0.1) < distance($1.1) }?.0 ?? "Custom"
  }

  /// Explicit scalar fields keep this format independent of the live color model
  /// and preserve the full Double precision, including alpha and customization.
  private struct PersistedPalette: Codable {
    let id: String
    let name: String
    let fill: PersistedColor
    let outline: PersistedColor
    let customized: Bool

    init(_ entry: SavedCursorPalette) {
      id = entry.id
      name = entry.name
      fill = PersistedColor(entry.colors.fill)
      outline = PersistedColor(entry.colors.outline)
      customized = entry.colors.customized
    }

    var colors: CursorColors? {
      let result = CursorColors(fill: fill.value, outline: outline.value, customized: customized)
      return result.isValid ? result : nil
    }
  }

  private struct PersistedColor: Codable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(_ value: CursorRGB) {
      red = value.red
      green = value.green
      blue = value.blue
      alpha = value.alpha
    }

    var value: CursorRGB {
      CursorRGB(red: red, green: green, blue: blue, alpha: alpha)
    }
  }

  /// An invalid record must not discard the other valid saved combinations.
  private struct DecodedPalette: Decodable {
    let value: PersistedPalette?
    init(from decoder: Decoder) throws {
      value = try? PersistedPalette(from: decoder)
    }
  }
}

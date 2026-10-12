import Foundation

/// Matches words in any order and treats punctuation and accents consistently.
enum SettingSearch {
  static func matches(_ text: String, query: String) -> Bool {
    let blob = normalized(text)
    let compact = blob.replacingOccurrences(of: " ", with: "")
    return normalized(query).split(separator: " ").allSatisfy {
      blob.contains($0) || compact.contains($0)
    }
  }

  static func normalized(_ text: String) -> String {
    text.folding(
      options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")
    )
    .components(separatedBy: CharacterSet.alphanumerics.inverted)
    .filter { !$0.isEmpty }.joined(separator: " ")
  }

  static func results(in specs: [ToggleSpec], query: String) -> [ToggleSpec] {
    let needle = normalized(query)
    guard !needle.isEmpty else { return specs }
    let words = needle.split(separator: " ").map(String.init)
    return specs.enumerated().compactMap { index, spec -> (Int, Int, ToggleSpec)? in
      let blob = normalized(spec.searchBlob)
      let compact = blob.replacingOccurrences(of: " ", with: "")
      guard words.allSatisfy({ blob.contains($0) || compact.contains($0) }) else { return nil }
      let title = normalized(spec.menuTitle)
      let rank = title == needle ? 0 : (title.contains(needle) ? 1 : 2)
      return (rank, index, spec)
    }
    .sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
    .map { $0.2 }
  }
}

enum ControlFilter: String, CaseIterable, Identifiable {
  case all = "All controls"
  case on = "On"
  case off = "Off"
  case unavailable = "Unavailable"

  var id: String { rawValue }

  func includes(_ state: ToggleState) -> Bool {
    switch self {
    case .all: return true
    case .on: return state.supported && !state.stale && state.isOn
    case .off: return state.supported && !state.stale && !state.isOn
    case .unavailable: return !state.supported && !state.stale
    }
  }
}

enum DropdownNavigation {
  enum Direction { case up, down, left, right }

  static func target(in columns: [[String]], current: String?, direction: Direction) -> String? {
    let flat = columns.flatMap { $0 }
    guard !flat.isEmpty else { return nil }
    guard let current, let index = flat.firstIndex(of: current) else { return flat.first }
    switch direction {
    case .up: return flat[max(0, index - 1)]
    case .down: return flat[min(flat.count - 1, index + 1)]
    case .left, .right:
      guard let column = columns.firstIndex(where: { $0.contains(current) }),
        let row = columns[column].firstIndex(of: current)
      else { return current }
      let adjacent = column + (direction == .left ? -1 : 1)
      guard columns.indices.contains(adjacent), !columns[adjacent].isEmpty else { return current }
      return columns[adjacent][min(row, columns[adjacent].count - 1)]
    }
  }
}

import AppKit
import Foundation

/// Keeps category groups intact and balances them across a compact panel.
@MainActor
enum DropdownLayout {
  enum Item: Identifiable {
    case header(Category)
    case row(ToggleSpec)
    case cursorColor
    case audioOutput

    var id: String {
      switch self {
      case .header(let category): return "h:\(category.rawValue)"
      case .row(let spec): return "r:\(spec.id)"
      case .cursorColor: return "c:cursorColor"
      case .audioOutput: return "c:audioOutput"
      }
    }
  }

  struct Metrics {
    var rowHeight: CGFloat
    var headerHeight: CGFloat = 30
    var chromeHeight: CGFloat = 168
    var columnWidth: CGFloat = 336
    var screenMargin: CGFloat = 24
    var showDescriptions: Bool

    init(showDescriptions: Bool) {
      self.showDescriptions = showDescriptions
      rowHeight = showDescriptions ? 66 : 42
    }
  }

  struct Result {
    var columns: [[Item]]
    var columnWidth: CGFloat
    var overflowed: Bool
    var width: CGFloat {
      CGFloat(max(1, columns.count)) * columnWidth + CGFloat(max(0, columns.count - 1)) * 16 + 24
    }
  }

  static var anchorScreen: NSScreen?
  static var layoutScreen: NSScreen? {
    anchorScreen ?? NSScreen.screens.first { $0.frame.origin == .zero }
      ?? NSScreen.screens.first ?? NSScreen.main
  }

  static func maxPopoverHeight() -> CGFloat {
    max(240, (layoutScreen?.visibleFrame.height ?? 800) - 16)
  }

  static func availableHeight(_ metrics: Metrics, screenSize: CGSize? = nil) -> CGFloat {
    let height = screenSize?.height ?? layoutScreen?.visibleFrame.height ?? 800
    return max(180, height - metrics.chromeHeight - metrics.screenMargin)
  }

  static func maxColumns(_ metrics: Metrics, screenSize: CGSize? = nil) -> Int {
    let width = screenSize?.width ?? layoutScreen?.visibleFrame.width ?? 1440
    return max(1, Int((width - metrics.screenMargin - 24 + 16) / (metrics.columnWidth + 16)))
  }

  static func pack(
    _ items: [Item], showDescriptions: Bool, extraChrome: CGFloat = 0, screenSize: CGSize? = nil
  ) -> Result {
    var metrics = Metrics(showDescriptions: showDescriptions)
    metrics.chromeHeight += extraChrome
    let width = screenSize?.width ?? layoutScreen?.visibleFrame.width ?? 1440
    metrics.columnWidth = min(336, max(180, width - 48))
    let cap = maxColumns(metrics, screenSize: screenSize)
    let rows = items.filter {
      if case .header = $0 { return false }
      return true
    }.count
    let preferred = rows > 12 && cap >= 2 ? 2 : 1
    let limit = availableHeight(metrics, screenSize: screenSize)
    var result = Result(columns: [], columnWidth: metrics.columnWidth, overflowed: false)
    for count in preferred...cap {
      result.columns = balanced(items, count: count, metrics: metrics)
      if result.columns.allSatisfy({ height($0, metrics: metrics) <= limit }) { return result }
    }
    result.overflowed = true
    return result
  }

  static func height(_ items: [Item], metrics: Metrics) -> CGFloat {
    items.reduce(0) { total, item in
      switch item {
      case .header: return total + metrics.headerHeight
      case .row(let spec):
        return total + spec.menuHeight(showDescriptions: metrics.showDescriptions)
      case .cursorColor, .audioOutput: return total + 40
      }
    }
  }

  private static func balanced(_ items: [Item], count: Int, metrics: Metrics) -> [[Item]] {
    guard !items.isEmpty else { return [] }
    let grouped = items.contains {
      if case .header = $0 { return true }
      return false
    }
    if !grouped {
      // A manually ordered flat menu reads down each column in the saved order.
      let size = max(1, Int(ceil(Double(items.count) / Double(count))))
      return stride(from: 0, to: items.count, by: size).map {
        Array(items[$0..<min(items.count, $0 + size)])
      }
    }
    var groups: [[Item]] = []
    for item in items {
      if case .header = item {
        groups.append([item])
      } else if groups.isEmpty {
        groups.append([item])
      } else {
        groups[groups.count - 1].append(item)
      }
    }
    // Seven categories make an exhaustive partition small. Minimize the tallest
    // column so a laptop does not need a third column just because of greedy packing.
    let columnCount = min(count, groups.count)
    let groupHeights = groups.map { height($0, metrics: metrics) }
    var columns = Array(repeating: [Item](), count: columnCount)
    var heights = Array(repeating: CGFloat.zero, count: columnCount)
    var best: [[Item]] = []
    var bestHeight = CGFloat.greatestFiniteMagnitude
    func distribute(_ groupIndex: Int) {
      if groupIndex == groups.count {
        let tallest = heights.max() ?? 0
        if tallest < bestHeight {
          bestHeight = tallest
          best = columns.filter { !$0.isEmpty }
        }
        return
      }
      for index in columns.indices {
        let wasEmpty = columns[index].isEmpty
        let nextHeight = heights[index] + groupHeights[groupIndex]
        if nextHeight < bestHeight {
          columns[index].append(contentsOf: groups[groupIndex])
          heights[index] = nextHeight
          distribute(groupIndex + 1)
          columns[index].removeLast(groups[groupIndex].count)
          heights[index] -= groupHeights[groupIndex]
        }
        // Empty columns are interchangeable.
        if wasEmpty { break }
      }
    }
    distribute(0)
    return best
  }
}

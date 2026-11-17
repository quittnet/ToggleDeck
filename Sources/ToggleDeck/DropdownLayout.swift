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

  /// Rendered sizes, in points. `height(_:metrics:)` must equal what
  /// `DropdownView` draws, because the popover is sized from it.
  struct Metrics {
    /// A title-only row; rows with a subtitle use `ToggleSpec.menuHeight`.
    var rowHeight: CGFloat
    /// A category label line, including the gap above it that separates it
    /// from the previous card.
    var headerHeight: CGFloat = 30
    /// Everything outside the columns: search header, column padding, and
    /// footer. See `DropdownChrome`.
    var chromeHeight: CGFloat = DropdownChrome.base
    var columnWidth: CGFloat = 336
    var screenMargin: CGFloat = 24
    var showDescriptions: Bool

    init(showDescriptions: Bool) {
      self.showDescriptions = showDescriptions
      rowHeight = showDescriptions ? 64 : 40
    }
  }

  /// Panel padding on each side of the columns.
  nonisolated static let horizontalPadding = 2 * DeckStyle.panelInset

  struct Result {
    var columns: [[Item]]
    var columnWidth: CGFloat
    var overflowed: Bool
    var width: CGFloat {
      CGFloat(max(1, columns.count)) * columnWidth
        + CGFloat(max(0, columns.count - 1)) * DeckStyle.columnSpacing + horizontalPadding
    }
  }

  static let cursorRowHeight: CGFloat = 40
  static let audioRowHeight: CGFloat = 40
  static let cursorAttentionRowHeight: CGFloat = 56

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
    return max(
      1,
      Int(
        (width - metrics.screenMargin - horizontalPadding + DeckStyle.columnSpacing)
          / (metrics.columnWidth + DeckStyle.columnSpacing)))
  }

  static func pack(
    _ items: [Item], showDescriptions: Bool, extraChrome: CGFloat = 0, screenSize: CGSize? = nil,
    cursorAttention: Bool = false
  ) -> Result {
    var metrics = Metrics(showDescriptions: showDescriptions)
    metrics.chromeHeight += extraChrome
    let width = screenSize?.width ?? layoutScreen?.visibleFrame.width ?? 1440
    metrics.columnWidth = min(336, max(180, width - metrics.screenMargin - horizontalPadding))
    let cap = maxColumns(metrics, screenSize: screenSize)
    let rows = items.filter {
      if case .header = $0 { return false }
      return true
    }.count
    let preferred = rows > 12 && cap >= 2 ? 2 : 1
    let limit = availableHeight(metrics, screenSize: screenSize)
    var result = Result(columns: [], columnWidth: metrics.columnWidth, overflowed: false)
    for count in preferred...cap {
      result.columns = balanced(
        items, count: count, metrics: metrics, cursorAttention: cursorAttention)
      if result.columns.allSatisfy({
        height($0, metrics: metrics, cursorAttention: cursorAttention) <= limit
      }) {
        return result
      }
    }
    result.overflowed = true
    return result
  }

  static func height(_ items: [Item], metrics: Metrics, cursorAttention: Bool = false) -> CGFloat {
    items.reduce(0) { total, item in
      switch item {
      case .header: return total + metrics.headerHeight
      case .row(let spec):
        return total + spec.menuHeight(showDescriptions: metrics.showDescriptions)
      case .cursorColor:
        return total + (cursorAttention ? cursorAttentionRowHeight : cursorRowHeight)
      case .audioOutput: return total + audioRowHeight
      }
    }
  }

  private static func balanced(
    _ items: [Item], count: Int, metrics: Metrics, cursorAttention: Bool = false
  ) -> [[Item]] {
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
    let groupHeights = groups.map {
      height($0, metrics: metrics, cursorAttention: cursorAttention)
    }
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

/// Fixed heights of the dropdown outside its columns. The view lays these
/// out with explicit frames so the layout engine can trust the sums.
enum DropdownChrome {
  static let searchHeight = DeckStyle.searchFieldHeight
  /// Panel top edge to search field, and search field to the columns' top
  /// padding.
  static let searchTopPadding = DeckStyle.panelInset
  static let searchBottomPadding: CGFloat = 8
  /// Above the first card or label, and below the last card.
  static let columnsTopPadding: CGFloat = 4
  static let columnsBottomPadding = DeckStyle.panelInset
  static let footerHeight: CGFloat = 38
  static let filterCaptionHeight: CGFloat = 24
  static let awakeStripHeight: CGFloat = 34
  static let awakeStripBottomPadding: CGFloat = 10
  static let bannerHeight: CGFloat = 108
  static let sceneChipHeight: CGFloat = 26
  static let sceneStripBottomPadding: CGFloat = 8
  static var sceneStrip: CGFloat { sceneChipHeight + sceneStripBottomPadding }

  static var header: CGFloat { searchTopPadding + searchHeight + searchBottomPadding }

  static var base: CGFloat {
    header + columnsTopPadding + columnsBottomPadding + footerHeight
  }
}

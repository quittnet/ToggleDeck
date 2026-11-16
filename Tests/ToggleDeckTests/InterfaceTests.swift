import AppKit
import Combine
import Testing

@testable import ToggleDeck

@MainActor
struct InterfaceTests {
  @Test
  func testRouterPublishesRequestedSection() {
    let router = SettingsRouter(section: .cursor)
    var published: [SettingsSection] = []
    let observation = router.$section.dropFirst().sink { published.append($0) }
    defer { observation.cancel() }

    router.request(.dropdown)
    #expect(router.section == .dropdown)
    #expect(published == [.dropdown])
  }

  @Test
  func testRouterIgnoresRepeatedRequestForSameSection() {
    let router = SettingsRouter()
    var changes = 0
    let observation = router.objectWillChange.sink { changes += 1 }
    defer { observation.cancel() }

    router.request(.dropdown)
    router.request(.sound)
    router.request(.sound)
    #expect(router.section == .sound)
    #expect(changes == 1)
  }

  @Test
  func testDropdownSessionCountsEachOpen() {
    let session = DropdownSession()
    var seen: [Int] = []
    let observation = session.$openCount.dropFirst().sink { seen.append($0) }
    defer { observation.cancel() }

    session.willOpen()
    session.willOpen()
    #expect(seen == [1, 2])
  }

  @Test
  func testBusyRowsStayNavigableButUnsupportedAndLoadingRowsDoNot() {
    #expect(DropdownNavigation.isNavigable(ToggleState(isOn: true, stale: false)))
    #expect(DropdownNavigation.isNavigable(ToggleState(isOn: true, busy: true, stale: false)))
    #expect(!DropdownNavigation.isNavigable(ToggleState(supported: false, stale: false)))
    #expect(!DropdownNavigation.isNavigable(ToggleState()))
  }

  @Test
  func testOnlyTheFirstStopLeadsBackToSearch() {
    let columns = [["a", "b"], ["c"]]
    #expect(DropdownNavigation.isFirst("a", in: columns))
    #expect(!DropdownNavigation.isFirst("b", in: columns))
    #expect(!DropdownNavigation.isFirst("c", in: columns))
    #expect(!DropdownNavigation.isFirst(nil, in: columns))
    #expect(!DropdownNavigation.isFirst("a", in: []))
    #expect(DropdownNavigation.isFirst("c", in: [[], ["c"]]))
  }

  /// A misspelled SF Symbol name draws nothing, which leaves an empty tile.
  @Test
  func testEveryTileSymbolExists() {
    var names = Catalog.all.flatMap { spec in
      [false, true].map { spec.menuSymbol(isOn: $0) }
    }
    let sections: [SettingsSection] =
      [.general, .dropdown, .cursor, .sound, .all] + Category.allCases.map { .category($0) }
    names += sections.map(\.symbol)
    for name in Set(names) {
      #expect(
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil,
        "No SF Symbol named \(name)")
    }
  }

  /// The popover is sized from these sums, so the rows the views draw at a
  /// fixed height have to be the heights the layout engine counts.
  @MainActor
  @Test
  func testLayoutCountsTheHeightsRowsAreDrawnAt() {
    let metrics = DropdownLayout.Metrics(showDescriptions: false)
    #expect(metrics.chromeHeight == DropdownChrome.base)
    #expect(DropdownChrome.searchHeight == DeckStyle.searchFieldHeight)
    for spec in Catalog.all {
      // Both sides as CGFloat: the macro compares a CGFloat and a Double as
      // unequal even when they hold the same value.
      let drawn = CGFloat(spec.menuHeight(showDescriptions: false))
      #expect(DropdownLayout.height([.row(spec)], metrics: metrics) == drawn)
    }
    #expect(
      DropdownLayout.height([.audioOutput], metrics: metrics) == DropdownLayout.audioRowHeight)
  }
}

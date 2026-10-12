import Foundation
import Testing

@testable import ToggleDeck

struct CursorLayoutTests {
  @MainActor
  @Test
  func testCursorSoundAndAllTogglesFitWithoutSplittingCategoryGroups() {
    let items = groupedItems()
    for (size, expectedColumns) in [
      (CGSize(width: 1280, height: 752), 3), (CGSize(width: 1920, height: 1156), 2),
    ] {
      let result = DropdownLayout.pack(items, showDescriptions: false, screenSize: size)
      #expect(result.columns.count == expectedColumns)
      #expect(!result.overflowed)
      #expect(result.width <= size.width)
      let metrics = DropdownLayout.Metrics(showDescriptions: false)
      let availableHeight = DropdownLayout.availableHeight(metrics, screenSize: size)
      #expect(
        result.columns.allSatisfy { DropdownLayout.height($0, metrics: metrics) <= availableHeight }
      )
      let packed = result.columns.flatMap { $0 }
      let boolIDs = packed.compactMap { item -> String? in
        if case .row(let spec) = item { return spec.id }
        return nil
      }
      #expect(boolIDs.count == 23)
      #expect(Set(boolIDs) == Set(Catalog.all.map(\.id)))
      #expect(packed.filter { $0.id == DropdownLayout.Item.cursorColor.id }.count == 1)
      #expect(packed.filter { $0.id == DropdownLayout.Item.audioOutput.id }.count == 1)
      #expect(packed.count == Catalog.all.count + 2 + Category.allCases.count)
      #expect(Set(packed.map(\.id)).count == packed.count)
      let categories = packed.compactMap { item -> ToggleDeck.Category? in
        if case .header(let category) = item { return category }
        return nil
      }
      #expect(categories.count == Category.allCases.count)
      #expect(Set(categories) == Set(Category.allCases))
      for column in result.columns {
        var activeCategory: ToggleDeck.Category?
        for item in column {
          switch item {
          case .header(let category): activeCategory = category
          case .row(let spec): #expect(spec.category == activeCategory)
          case .cursorColor: #expect(activeCategory == .display)
          case .audioOutput: #expect(activeCategory == .connections)
          }
        }
      }
      for category in Category.allCases {
        let categoryIDs = packed.compactMap { item -> String? in
          if case .row(let spec) = item, spec.category == category { return spec.id }
          return nil
        }
        #expect(categoryIDs == Catalog.all.filter { $0.category == category }.map(\.id))
      }
    }
  }

  @MainActor
  @Test
  func testCursorRowHasStableDistinctIdentityAndFixedHeight() {
    let cursor = DropdownLayout.Item.cursorColor
    let audio = DropdownLayout.Item.audioOutput
    #expect(cursor.id == "c:cursorColor")
    #expect(audio.id == "c:audioOutput")
    #expect(audio.id != cursor.id)
    #expect(!Catalog.all.map { DropdownLayout.Item.row($0).id }.contains(cursor.id))
    #expect(!Category.allCases.map { DropdownLayout.Item.header($0).id }.contains(cursor.id))
    for showDescriptions in [false, true] {
      let metrics = DropdownLayout.Metrics(showDescriptions: showDescriptions)
      #expect(DropdownLayout.height([cursor], metrics: metrics) == 40)
      #expect(DropdownLayout.height([audio], metrics: metrics) == 40)
      let result = DropdownLayout.pack(
        [cursor], showDescriptions: showDescriptions,
        screenSize: CGSize(width: 1280, height: 752))
      #expect(result.columns.count == 1)
      #expect(result.columns.flatMap { $0 }.map(\.id) == [cursor.id])
      #expect(!result.overflowed)
    }
  }

  @Test
  func testCursorKeywordsSupportMultiwordSearchAndExcludeUnrelatedWiFi() {
    for query in [
      "pointer color", "cursor red", "outline mouse", "MÓUSE FILL", "blue cursor", "pointer size",
      "shake locate",
    ] {
      #expect(CursorPreset.matchesSearch(query))
    }
    #expect(CursorPreset.matchesSearch(""))
    #expect(!CursorPreset.matchesSearch("wifi"))
    #expect(!CursorPreset.matchesSearch("cursor wifi"))
    let wifiKeywords = Catalog.byID["wifi"]?.searchBlob ?? ""
    #expect(!wifiKeywords.isEmpty)
    #expect(!SettingSearch.matches(wifiKeywords, query: "pointer color"))
    #expect(!SettingSearch.matches(wifiKeywords, query: "cursor red"))
  }

  @MainActor
  private func groupedItems() -> [DropdownLayout.Item] {
    Category.allCases.flatMap { category -> [DropdownLayout.Item] in
      let controls = Catalog.all.filter { $0.category == category }.map {
        DropdownLayout.Item.row($0)
      }
      return [.header(category)] + controls + (category == .display ? [.cursorColor] : [])
        + (category == .connections ? [.audioOutput] : [])
    }
  }
}

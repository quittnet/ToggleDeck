import Foundation
import Testing

@testable import ToggleDeck

@Suite(.serialized)
struct CursorPaletteTests {
  @MainActor
  @Test
  func testSavedRedFillAndYellowOutlineRetainExactComponentsAfterReload() throws {
    try withIsolatedStore { defaults in
      let palette = CursorPaletteStore(store: defaults)
      let colors = CursorColors(
        fill: CursorPreset.red.colors.fill, outline: CursorPreset.yellow.colors.fill,
        customized: true)
      let saved = try #require(palette.save(colors, name: "Red and Yellow"))
      let reloaded = CursorPaletteStore(store: defaults)
      #expect(reloaded.savedColors.count == 1)
      #expect(reloaded.savedColors.first?.id == saved.id)
      #expect(reloaded.savedColors.first?.name == "Red and Yellow")
      #expect(reloaded.savedColors.first?.colors == colors)
      #expect(reloaded.matching(colors)?.id == saved.id)
    }
  }

  @MainActor
  @Test
  func testSavedCustomColorsRetainAlphaAndFractionalComponents() throws {
    try withIsolatedStore { defaults in
      let colors = CursorColors(
        fill: CursorRGB(red: 0.123456789, green: 0.456789123, blue: 0.987654321, alpha: 0.625),
        outline: CursorRGB(red: 0.765432198, green: 0.234567891, blue: 0.345678912, alpha: 0.875),
        customized: true)
      let palette = CursorPaletteStore(store: defaults)
      let saved = try #require(palette.save(colors))
      let reloaded = CursorPaletteStore(store: defaults)
      #expect(reloaded.savedColors.first?.colors == colors)
      #expect(reloaded.matching(colors)?.id == saved.id)
    }
  }

  @MainActor
  @Test
  func testNearDuplicatePreservesExistingIdentityNameAndExactSavedColors() throws {
    try withIsolatedStore { defaults in
      let palette = CursorPaletteStore(store: defaults)
      let original = CursorColors(
        fill: CursorRGB(red: 0.35, green: 0.45, blue: 0.55),
        outline: CursorRGB(red: 0.65, green: 0.75, blue: 0.85), customized: true)
      let saved = try #require(palette.save(original, name: "My Colors"))
      let near = CursorColors(
        fill: CursorRGB(red: 0.35005, green: 0.44995, blue: 0.55005),
        outline: original.outline, customized: true)
      let duplicate = try #require(palette.save(near))
      #expect(duplicate.id == saved.id)
      #expect(duplicate.name == "My Colors")
      #expect(duplicate.colors == original)
      #expect(palette.savedColors.count == 1)
      #expect(palette.matching(near)?.id == saved.id)
      #expect(CursorPaletteStore(store: defaults).savedColors.first?.id == saved.id)
    }
  }

  @MainActor
  @Test
  func testExplicitRenameUpdatesSameSavedCombinationAndPersists() throws {
    try withIsolatedStore { defaults in
      let palette = CursorPaletteStore(store: defaults)
      let colors = CursorPreset.purple.colors
      let original = try #require(palette.save(colors, name: "First Name"))
      let renamed = try #require(palette.save(colors, name: "Second Name"))
      #expect(renamed.id == original.id)
      #expect(renamed.name == "Second Name")
      #expect(renamed.colors == colors)
      #expect(palette.savedColors.count == 1)
      let reloaded = CursorPaletteStore(store: defaults)
      #expect(reloaded.savedColors.first?.name == "Second Name")
      #expect(reloaded.savedColors.first?.id == original.id)
    }
  }

  @MainActor
  @Test
  func testDistinctOutlinesNeverOverwriteSavedCombination() throws {
    try withIsolatedStore { defaults in
      let palette = CursorPaletteStore(store: defaults)
      let first = CursorColors(
        fill: CursorPreset.red.colors.fill, outline: .white, customized: true)
      let second = CursorColors(
        fill: first.fill, outline: CursorPreset.yellow.colors.fill, customized: true)
      let firstSaved = try #require(palette.save(first, name: "Red and White"))
      let secondSaved = try #require(palette.save(second, name: "Red and Yellow"))
      #expect(firstSaved.id != secondSaved.id)
      #expect(palette.savedColors.count == 2)
      #expect(palette.matching(first)?.id == firstSaved.id)
      #expect(palette.matching(second)?.id == secondSaved.id)
      let reloaded = CursorPaletteStore(store: defaults)
      #expect(Set(reloaded.savedColors.map(\.id)) == [firstSaved.id, secondSaved.id])
      #expect(reloaded.matching(first)?.colors == first)
      #expect(reloaded.matching(second)?.colors == second)
    }
  }

  @MainActor
  @Test
  func testRemovingSavedColorPersistsAndPreservesOtherEntries() throws {
    try withIsolatedStore { defaults in
      let palette = CursorPaletteStore(store: defaults)
      let red = try #require(palette.save(CursorPreset.red.colors))
      let green = try #require(palette.save(CursorPreset.green.colors))
      palette.remove(red.id)
      palette.remove("does-not-exist")
      let reloaded = CursorPaletteStore(store: defaults)
      #expect(reloaded.savedColors.count == 1)
      #expect(reloaded.savedColors.first?.id == green.id)
      #expect(reloaded.matching(CursorPreset.red.colors) == nil)
      #expect(reloaded.matching(CursorPreset.green.colors)?.id == green.id)
    }
  }

  @MainActor
  @Test
  func testPreviewPalettesStayIndependentAndInMemory() throws {
    let first = CursorPaletteStore.preview()
    let second = CursorPaletteStore.preview()
    let saved = try #require(first.save(CursorPreset.blue.colors, name: "Preview Blue"))
    #expect(first.savedColors.count == 1)
    #expect(first.matching(CursorPreset.blue.colors)?.id == saved.id)
    #expect(second.savedColors.isEmpty)
    #expect(CursorPaletteStore.preview().savedColors.isEmpty)
    first.remove(saved.id)
    #expect(first.savedColors.isEmpty)
    #expect(second.savedColors.isEmpty)
  }

  @MainActor
  @Test
  func testInvalidColorsAreRejectedWithoutPollutingStoredPalette() throws {
    try withIsolatedStore { defaults in
      let palette = CursorPaletteStore(store: defaults)
      let valid = try #require(palette.save(CursorPreset.pink.colors, name: "Keep This"))
      let invalidChannels = [
        CursorRGB(red: -.infinity, green: 0, blue: 0),
        CursorRGB(red: 0, green: .nan, blue: 0),
        CursorRGB(red: 0, green: 0, blue: 1.001),
        CursorRGB(red: 0, green: 0, blue: 0, alpha: -0.01),
        CursorRGB(red: 0, green: 0, blue: 0, alpha: .infinity),
      ]
      for invalid in invalidChannels {
        #expect(palette.save(CursorColors(fill: invalid, outline: .white, customized: true)) == nil)
        #expect(palette.save(CursorColors(fill: .black, outline: invalid, customized: true)) == nil)
      }
      #expect(palette.savedColors.count == 1)
      #expect(palette.savedColors.first?.id == valid.id)
      let reloaded = CursorPaletteStore(store: defaults)
      #expect(reloaded.savedColors.count == 1)
      #expect(reloaded.savedColors.first?.colors == valid.colors)
    }
  }

  @MainActor
  @Test
  func testBlankNameGetsReadableFallbackAndCannotEraseExistingName() throws {
    let palette = CursorPaletteStore.preview()
    let colors = CursorColors(
      fill: CursorRGB(red: 0.15, green: 0.35, blue: 0.65),
      outline: CursorRGB(red: 0.95, green: 0.75, blue: 0.25), customized: true)
    let generated = try #require(palette.save(colors, name: " \n\t "))
    #expect(!generated.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    #expect(generated.name == generated.name.trimmingCharacters(in: .whitespacesAndNewlines))
    let renamed = try #require(palette.save(colors, name: "  Evening Cursor  "))
    #expect(renamed.name == "Evening Cursor")
    #expect(renamed.id == generated.id)
    let blankRename = try #require(palette.save(colors, name: " \n "))
    #expect(blankRename.id == renamed.id)
    #expect(blankRename.name == "Evening Cursor")
  }

  @MainActor
  @Test
  func testDefaultNamesDescribeRedAndYellowAndNormalizeCustomNames() throws {
    let palette = CursorPaletteStore.preview()
    let colors = CursorColors(
      fill: CursorPreset.red.colors.fill, outline: CursorPreset.yellow.colors.fill,
      customized: true)
    let saved = try #require(palette.save(colors))
    #expect(saved.name == "Red & Yellow")
    let renamed = try #require(palette.save(colors, name: "  Red\n\tand   Yellow  "))
    #expect(renamed.name == "Red and Yellow")
    #expect(renamed.id == saved.id)
  }

  @MainActor
  @Test
  func testDefaultAndCustomizedBlackAndWhiteRetainDistinctSavedStates() throws {
    try withIsolatedStore { defaults in
      let palette = CursorPaletteStore(store: defaults)
      let standard = try #require(palette.save(.standard))
      let custom = CursorColors(fill: .black, outline: .white, customized: true)
      let customized = try #require(palette.save(custom))
      #expect(standard.id != customized.id)
      #expect(standard.name == "Default")
      let reloaded = CursorPaletteStore(store: defaults)
      #expect(reloaded.savedColors.count == 2)
      #expect(reloaded.matching(.standard)?.colors.customized == false)
      #expect(reloaded.matching(custom)?.colors.customized == true)
      #expect(reloaded.matching(.standard)?.id == standard.id)
      #expect(reloaded.matching(custom)?.id == customized.id)
    }
  }

  @MainActor
  @Test
  func testMalformedPersistedDataIsIgnoredAndSavingCanRecover() throws {
    try withIsolatedStore { defaults in
      defaults.set(Data("{broken json".utf8), forKey: CursorPaletteStore.storageKey)
      let palette = CursorPaletteStore(store: defaults)
      #expect(palette.savedColors.isEmpty)
      let saved = try #require(palette.save(CursorPreset.green.colors, name: "Recovered"))
      let reloaded = CursorPaletteStore(store: defaults)
      #expect(reloaded.savedColors.count == 1)
      #expect(reloaded.savedColors.first?.id == saved.id)
      #expect(reloaded.savedColors.first?.colors == CursorPreset.green.colors)
      defaults.set("wrong defaults type", forKey: CursorPaletteStore.storageKey)
      #expect(CursorPaletteStore(store: defaults).savedColors.isEmpty)
    }
  }

  @MainActor
  @Test
  func testMalformedRecordsAndDuplicatesDoNotDiscardValidSavedCombinations() throws {
    try withIsolatedStore { defaults in
      let blueID = UUID().uuidString
      let pinkID = UUID().uuidString
      let blue = persistedRecord(id: blueID, name: "Blue", colors: CursorPreset.blue.colors)
      let pink = persistedRecord(id: pinkID, name: "Pink", colors: CursorPreset.pink.colors)
      var booleanChannel = persistedRecord(
        id: UUID().uuidString, name: "Boolean Channel", colors: CursorPreset.green.colors)
      booleanChannel["fill"] = ["red": 0.22, "green": 0.78, "blue": 0.37, "alpha": true]
      var missingChannel = persistedRecord(
        id: UUID().uuidString, name: "Missing Channel", colors: CursorPreset.green.colors)
      missingChannel["outline"] = ["red": 0, "green": 0, "alpha": 1]
      var outOfRange = persistedRecord(
        id: UUID().uuidString, name: "Out of Range", colors: CursorPreset.green.colors)
      outOfRange["fill"] = ["red": 1.01, "green": 0.78, "blue": 0.37, "alpha": 1]
      let records: [Any] = [
        blue, booleanChannel, "not a palette", missingChannel, outOfRange,
        persistedRecord(id: "not-a-uuid", name: "Invalid ID", colors: CursorPreset.red.colors),
        persistedRecord(id: UUID().uuidString, name: " \n ", colors: CursorPreset.yellow.colors),
        persistedRecord(id: blueID, name: "Duplicate ID", colors: CursorPreset.red.colors),
        persistedRecord(
          id: UUID().uuidString, name: "Duplicate Color", colors: CursorPreset.blue.colors),
        pink,
      ]
      defaults.set(
        try JSONSerialization.data(withJSONObject: records), forKey: CursorPaletteStore.storageKey)
      let palette = CursorPaletteStore(store: defaults)
      #expect(palette.savedColors.map(\.id) == [blueID, pinkID])
      #expect(palette.matching(CursorPreset.blue.colors)?.name == "Blue")
      #expect(palette.matching(CursorPreset.pink.colors)?.name == "Pink")
      #expect(palette.matching(CursorPreset.green.colors) == nil)
      let extra = try #require(palette.save(CursorPreset.red.colors, name: "New Red"))
      let reloaded = CursorPaletteStore(store: defaults)
      #expect(reloaded.savedColors.map(\.id) == [blueID, pinkID, extra.id])
    }
  }

  @Test
  func testSolidPresetsRemainAndCombinationPresetsAreValidUniqueAndSearchable() {
    #expect(
      CursorPreset.solidPresets == [
        .standard, .white, .red, .orange, .yellow, .green, .blue, .purple, .pink,
      ])
    #expect(CursorPreset.solidPresets.count == 9)
    #expect(CursorPreset.combinationPresets == [.fire, .ocean, .mint, .royal, .candy])
    #expect(CursorPreset.combinationPresets.count == 5)
    #expect(CursorPreset.allCases.count == 14)
    #expect(Set(CursorPreset.allCases.map(\.id)).count == 14)
    #expect(CursorPreset.red.colors.fill == CursorRGB(red: 0.95, green: 0.18, blue: 0.22))
    #expect(CursorPreset.yellow.colors.fill == CursorRGB(red: 1, green: 0.86, blue: 0.1))
    for preset in CursorPreset.combinationPresets {
      #expect(preset.isCombination)
      #expect(preset.colors.isValid)
      #expect(preset.colors.customized)
      #expect(!preset.colors.fill.matches(preset.colors.outline))
      #expect(CursorPreset.matching(preset.colors) == preset)
      #expect(CursorPreset.matchesSearch("\(preset.rawValue.lowercased()) cursor"))
      #expect(CursorPreset.matchesSearch("pointer \(preset.rawValue.uppercased())"))
      for other in CursorPreset.allCases where other != preset {
        #expect(!preset.colors.matches(other.colors))
      }
    }
    #expect(CursorPreset.solidPresets.allSatisfy { !$0.isCombination })
    #expect(!CursorPreset.matchesSearch("fire wifi"))
  }

  @MainActor
  @Test
  func testControllerImportsExactCurrentCustomColorsAndSurvivesReload() async throws {
    try await withIsolatedAsyncStore { defaults in
      let colors = CursorColors(
        fill: CursorPreset.red.colors.fill, outline: CursorPreset.yellow.colors.fill,
        customized: true)
      let backend = PaletteControllerBackend(colors: colors)
      let palette = CursorPaletteStore(store: defaults)
      let controller = makeController(using: backend, palettes: palette)
      #expect(palette.savedColors.isEmpty)
      await controller.refresh()
      let imported = try #require(palette.matching(colors))
      #expect(imported.colors == colors)
      #expect(imported.name == "Red & Yellow")
      #expect(controller.selectionName == imported.name)
      let reloadedPalette = CursorPaletteStore(store: defaults)
      let reloadedController = makeController(using: backend, palettes: reloadedPalette)
      await reloadedController.refresh()
      #expect(reloadedPalette.savedColors.count == 1)
      #expect(reloadedPalette.matching(colors)?.id == imported.id)
      #expect(reloadedPalette.matching(colors)?.colors == colors)
      #expect(reloadedController.selectionName == imported.name)
      #expect(reloadedController.colors == colors)
      let writes = await backend.writeCount
      #expect(writes == 0)
    }
  }

  @MainActor
  @Test
  func testControllerSavesConfirmedCustomReadbackAndIgnoresFailedRequest() async throws {
    try await withIsolatedAsyncStore { defaults in
      let backend = PaletteControllerBackend(colors: .standard)
      let palette = CursorPaletteStore(store: defaults)
      let controller = makeController(using: backend, palettes: palette)
      await controller.refresh()
      #expect(palette.savedColors.isEmpty)
      let requested = CursorColors(
        fill: CursorPreset.red.colors.fill, outline: CursorPreset.yellow.colors.fill,
        customized: true)
      await backend.setFailure("macOS rejected the custom cursor.")
      await controller.apply(requested)
      #expect(controller.error == "macOS rejected the custom cursor.")
      #expect(controller.colors == .standard)
      #expect(palette.savedColors.isEmpty)
      #expect(CursorPaletteStore(store: defaults).savedColors.isEmpty)
      let verified = CursorColors(
        fill: CursorRGB(
          red: requested.fill.red - 0.00004, green: requested.fill.green,
          blue: requested.fill.blue),
        outline: requested.outline, customized: true)
      await backend.setFailure(nil)
      await backend.setWriteOverride(verified)
      await controller.apply(requested)
      #expect(controller.error == nil)
      #expect(controller.colors == verified)
      #expect(palette.savedColors.count == 1)
      #expect(palette.savedColors.first?.colors == verified)
      #expect(palette.savedColors.first?.colors != requested)
      #expect(controller.selectionName == palette.savedColors.first?.name)
      #expect(CursorPaletteStore(store: defaults).savedColors.first?.colors == verified)
      let writes = await backend.writeCount
      #expect(writes == 2)
    }
  }

  @MainActor
  @Test
  func testControllerUsesSavedNameAndRefreshCannotOverwriteRename() async throws {
    try await withIsolatedAsyncStore { defaults in
      let colors = CursorColors(
        fill: CursorPreset.red.colors.fill, outline: CursorPreset.yellow.colors.fill,
        customized: true)
      let backend = PaletteControllerBackend(colors: colors)
      let palette = CursorPaletteStore(store: defaults)
      let original = try #require(palette.save(colors, name: "My Red and Yellow"))
      let controller = makeController(using: backend, palettes: palette)
      await controller.refresh()
      #expect(controller.selectionName == "My Red and Yellow")
      let renamed = try #require(palette.save(colors, name: "Evening Cursor"))
      #expect(renamed.id == original.id)
      #expect(controller.selectionName == "Evening Cursor")
      await controller.refresh(clearError: false)
      #expect(controller.selectionName == "Evening Cursor")
      #expect(palette.savedColors.count == 1)
      await backend.setColors(CursorPreset.blue.colors)
      await controller.refresh()
      #expect(controller.selectionName == "Blue")
      #expect(palette.savedColors.count == 1)
      await backend.setColors(colors)
      await controller.refresh()
      #expect(controller.selectionName == "Evening Cursor")
      #expect(CursorPaletteStore(store: defaults).matching(colors)?.name == "Evening Cursor")
    }
  }

  @MainActor
  private func makeController(
    using backend: PaletteControllerBackend, palettes: CursorPaletteStore
  ) -> CursorColorController {
    CursorColorController(
      reader: { await backend.read() }, writer: { await backend.write($0) }, palettes: palettes)
  }

  private func persistedRecord(id: String, name: String, colors: CursorColors) -> [String: Any] {
    func channels(_ color: CursorRGB) -> [String: Double] {
      ["red": color.red, "green": color.green, "blue": color.blue, "alpha": color.alpha]
    }
    return [
      "id": id, "name": name, "fill": channels(colors.fill), "outline": channels(colors.outline),
      "customized": colors.customized,
    ]
  }

  @MainActor
  private func withIsolatedStore(_ body: (UserDefaults) throws -> Void) throws {
    let suite = "com.user.toggledeck.palette.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(defaults)
  }

  @MainActor
  private func withIsolatedAsyncStore(
    _ body: @MainActor (UserDefaults) async throws -> Void
  ) async throws {
    let suite = "com.user.toggledeck.palette.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try await body(defaults)
  }
}

private actor PaletteControllerBackend {
  private var colors: CursorColors
  private var failure: String?
  private var writeOverride: CursorColors?
  private(set) var writeCount = 0

  init(colors: CursorColors) { self.colors = colors }

  func read() -> CursorColors? { colors }
  func setColors(_ colors: CursorColors) { self.colors = colors }
  func setFailure(_ value: String?) { failure = value }
  func setWriteOverride(_ colors: CursorColors?) { writeOverride = colors }

  func write(_ colors: CursorColors) -> String? {
    writeCount += 1
    if let failure { return failure }
    self.colors = writeOverride ?? colors
    return nil
  }
}

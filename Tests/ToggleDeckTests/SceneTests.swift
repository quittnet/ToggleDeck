import Foundation
import Testing

@testable import ToggleDeck

@MainActor
@Suite
struct SceneTests {
  private func withStore(_ body: (UserDefaults) -> Void) {
    let suite = "com.user.toggledeck.tests.\(UUID().uuidString)"
    let store = UserDefaults(suiteName: suite)!
    defer { store.removePersistentDomain(forName: suite) }
    body(store)
  }

  @Test
  func testScenesPersistAcrossLaunches() {
    withStore { store in
      let first = SceneStore(store: store)
      let scene = first.add(.presenting)
      first.scenes[0].name = "Demo"
      let second = SceneStore(store: store)
      #expect(second.scenes.count == 1)
      #expect(second.scenes[0].id == scene.id)
      #expect(second.scenes[0].name == "Demo")
      #expect(second.scenes[0].targets == DeckScene.presenting.targets)
    }
  }

  @Test
  func testDecodeDropsRetiredAndRepeatedSwitches() throws {
    let saved = [
      DeckScene(
        name: "Old",
        targets: [
          SceneTarget(id: "darkMode", on: true), SceneTarget(id: "retiredSwitch", on: true),
          SceneTarget(id: "darkMode", on: false),
        ])
    ]
    let decoded = SceneStore.decode(try JSONEncoder().encode(saved))
    #expect(decoded.first?.targets == [SceneTarget(id: "darkMode", on: true)])
    #expect(SceneStore.decode(Data("not json".utf8)).isEmpty)
    #expect(SceneStore.decode(nil).isEmpty)
  }

  @Test
  func testNewScenesGetUniqueNames() {
    let scenes = SceneStore.preview()
    scenes.add()
    scenes.add()
    scenes.remove(scenes.scenes[0].id)
    scenes.add()
    #expect(scenes.scenes.map(\.name) == ["Scene 2", "Scene 3"])
  }

  @Test
  func testApplySetsOnlyListedSwitchesAndThenReadsActive() async {
    let engine = ToggleEngine.preview(states: [
      "darkMode": ToggleState(isOn: false, stale: false),
      "nightShift": ToggleState(isOn: true, stale: false),
      "showHiddenFiles": ToggleState(isOn: false, stale: false),
    ])
    let scene = DeckScene(
      name: "Evening",
      targets: [SceneTarget(id: "darkMode", on: true), SceneTarget(id: "nightShift", on: true)])
    let scenes = SceneStore.preview([scene])
    #expect(!SceneStore.isActive(scene, engine: engine))
    #expect(SceneStore.pendingChanges(scene, engine: engine).map(\.id) == ["darkMode"])

    await scenes.apply(scene, engine: engine)
    #expect(engine.state("darkMode").isOn)
    #expect(engine.state("nightShift").isOn)
    #expect(!engine.state("showHiddenFiles").isOn, "A switch outside the scene is untouched.")
    #expect(SceneStore.isActive(scene, engine: engine))
    #expect(scenes.applying == nil)
  }

  @Test
  func testUnsupportedSwitchIsSkippedAndKeepsSceneInactive() {
    let engine = ToggleEngine.preview(states: [
      "darkMode": ToggleState(isOn: true, stale: false),
      "trueTone": ToggleState(isOn: false, supported: false, stale: false),
    ])
    let scene = DeckScene(
      name: "Mixed",
      targets: [SceneTarget(id: "darkMode", on: true), SceneTarget(id: "trueTone", on: true)])
    #expect(SceneStore.pendingChanges(scene, engine: engine).isEmpty)
    #expect(!SceneStore.isActive(scene, engine: engine))
    #expect(!SceneStore.isActive(DeckScene(name: "Empty"), engine: engine))
  }

  @Test
  func testAddedSwitchFlipsAndCaptureCopiesCurrentPositions() {
    let engine = ToggleEngine.preview(states: [
      "darkMode": ToggleState(isOn: true, stale: false),
      "dockAutohide": ToggleState(isOn: false, stale: false),
    ])
    let scenes = SceneStore.preview([DeckScene(name: "Test")])
    let id = scenes.scenes[0].id
    scenes.addTarget("darkMode", to: id, engine: engine)
    scenes.addTarget("darkMode", to: id, engine: engine)
    scenes.addTarget("notASwitch", to: id, engine: engine)
    scenes.addTarget("dockAutohide", to: id, engine: engine)
    #expect(
      scenes.scenes[0].targets == [
        SceneTarget(id: "darkMode", on: false), SceneTarget(id: "dockAutohide", on: true),
      ])

    scenes.capture(id, engine: engine)
    #expect(
      scenes.scenes[0].targets == [
        SceneTarget(id: "darkMode", on: true), SceneTarget(id: "dockAutohide", on: false),
      ])
    scenes.removeTarget("darkMode", from: id)
    #expect(scenes.scenes[0].targets.map(\.id) == ["dockAutohide"])
  }
}

import Foundation

/// One switch a scene sets, and the position it sets it to.
struct SceneTarget: Codable, Equatable, Sendable {
  var id: String
  var on: Bool
}

/// A named set of switch positions applied together from the menu.
/// Named `DeckScene` because SwiftUI already exports a `Scene` protocol.
struct DeckScene: Codable, Equatable, Identifiable, Sendable {
  var id = UUID()
  var name: String
  var targets: [SceneTarget] = []

  /// Switches this scene sets that the catalog still knows, without repeats.
  var specs: [ToggleSpec] { targets.compactMap { Catalog.byID[$0.id] } }

  func contains(_ id: String) -> Bool { targets.contains { $0.id == id } }

  /// Starter scene offered when the list is empty: a tidy screen for sharing.
  static var presenting: DeckScene {
    DeckScene(
      name: "Presenting",
      targets: [
        SceneTarget(id: "showDesktopIcons", on: false),
        SceneTarget(id: "dockAutohide", on: true),
        SceneTarget(id: "screenshotThumbnail", on: false),
        SceneTarget(id: "keepAwake", on: true),
      ])
  }
}

/// Saved scenes, persisted as JSON in ToggleDeck's own defaults.
@MainActor
final class SceneStore: ObservableObject {
  static let shared = SceneStore()
  static let storageKey = "scenes"

  private let store: UserDefaults?

  @Published var scenes: [DeckScene] { didSet { save() } }
  /// The scene being applied. Only one runs at a time.
  @Published private(set) var applying: UUID?

  init(store: UserDefaults? = UserDefaults.standard) {
    self.store = store
    scenes = Self.decode(store?.data(forKey: Self.storageKey))
  }

  static func preview(_ scenes: [DeckScene] = []) -> SceneStore {
    let model = SceneStore(store: nil)
    model.scenes = scenes
    return model
  }

  /// Drops switches a newer build removed from the catalog, and repeats of
  /// one switch, so an old save can never write to an unknown control.
  nonisolated static func decode(_ data: Data?) -> [DeckScene] {
    guard let data, let decoded = try? JSONDecoder().decode([DeckScene].self, from: data)
    else { return [] }
    return decoded.map { scene in
      var seen = Set<String>()
      var cleaned = scene
      cleaned.targets = scene.targets.filter {
        Catalog.byID[$0.id] != nil && seen.insert($0.id).inserted
      }
      return cleaned
    }
  }

  private func save() {
    guard let store, let data = try? JSONEncoder().encode(scenes) else { return }
    store.set(data, forKey: Self.storageKey)
  }

  // MARK: Editing

  @discardableResult
  func add(_ scene: DeckScene? = nil) -> DeckScene {
    let existing = Set(scenes.map(\.name))
    var number = scenes.count + 1
    while existing.contains("Scene \(number)") { number += 1 }
    let new = scene ?? DeckScene(name: "Scene \(number)")
    scenes.append(new)
    return new
  }

  func remove(_ id: UUID) { scenes.removeAll { $0.id == id } }

  /// Adds a switch set to the opposite of where it is now, so a new entry
  /// changes something the first time the scene runs.
  func addTarget(_ switchID: String, to sceneID: UUID, engine: ToggleEngine) {
    guard Catalog.byID[switchID] != nil,
      let index = scenes.firstIndex(where: { $0.id == sceneID }),
      !scenes[index].contains(switchID)
    else { return }
    scenes[index].targets.append(SceneTarget(id: switchID, on: !engine.state(switchID).isOn))
  }

  func removeTarget(_ switchID: String, from sceneID: UUID) {
    guard let index = scenes.firstIndex(where: { $0.id == sceneID }) else { return }
    scenes[index].targets.removeAll { $0.id == switchID }
  }

  /// Copies every readable switch's current position into the scene.
  func capture(_ sceneID: UUID, engine: ToggleEngine) {
    guard let index = scenes.firstIndex(where: { $0.id == sceneID }) else { return }
    for (position, target) in scenes[index].targets.enumerated() {
      let state = engine.state(target.id)
      guard state.supported, !state.stale else { continue }
      scenes[index].targets[position].on = state.isOn
    }
  }

  // MARK: Applying

  /// Switches whose known position differs from the scene's. Unknown or
  /// unsupported switches are left out rather than guessed at.
  static func pendingChanges(_ scene: DeckScene, engine: ToggleEngine) -> [SceneTarget] {
    scene.targets.filter { target in
      let state = engine.state(target.id)
      return Catalog.byID[target.id] != nil && state.supported && !state.stale
        && state.isOn != target.on
    }
  }

  /// True when every switch the scene sets is readable and already in place.
  static func isActive(_ scene: DeckScene, engine: ToggleEngine) -> Bool {
    !scene.targets.isEmpty
      && scene.targets.allSatisfy { target in
        let state = engine.state(target.id)
        return state.supported && !state.stale && state.isOn == target.on
      }
  }

  func apply(_ scene: DeckScene, engine: ToggleEngine) async {
    guard applying == nil else { return }
    applying = scene.id
    defer { applying = nil }

    // A switch not yet read cannot be written, so read it first.
    for target in scene.targets where engine.state(target.id).stale {
      await engine.refresh(target.id, clearError: false)
    }
    let changes = Self.pendingChanges(scene, engine: engine)
    let needsAdmin = Set(changes.filter { Catalog.byID[$0.id]?.needsAdmin == true }.map(\.id))

    // Ordinary writes run together, so their Dock or Finder restarts land in
    // one coalesced pass. Writes that ask for a password go one at a time,
    // after, so two authorization prompts never stack.
    await withTaskGroup(of: Void.self) { group in
      for target in changes where !needsAdmin.contains(target.id) {
        group.addTask { await engine.set(target.id, on: target.on) }
      }
    }
    for target in changes where needsAdmin.contains(target.id) {
      await engine.set(target.id, on: target.on)
    }
  }
}

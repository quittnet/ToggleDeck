import Foundation
import SwiftUI

/// Owns the live state of every catalog entry: reads it, writes it, and verifies
/// that the write actually landed.
///
/// Verification is not optional politeness. Several domains (universalaccess,
/// Safari, TimeMachine) accept a `defaults write` and silently discard it unless
/// the app holds Full Disk Access, so the only honest way to report success is
/// to read the value back.
@MainActor
final class ToggleEngine: ObservableObject {
  static let shared = ToggleEngine()

  @Published private(set) var states: [String: ToggleState] = [:]
  @Published private(set) var isRefreshing = false
  /// Most recent failure, surfaced as a banner.
  @Published var banner: String?

  private var bannerControlID: String?
  private var pendingRestarts: Set<Service> = []
  private var restartWorkItem: DispatchWorkItem?
  /// Bumped on every scheduled restart so a superseded work item can tell it has
  /// been replaced and do nothing.
  private var restartGeneration = 0
  @Published private(set) var lastRefreshed: Date?
  @Published private(set) var keepAwakeUntil: Date?

  typealias Reader = @Sendable (ToggleSpec, Bool) async -> ToggleState
  typealias Writer = @Sendable (ToggleSpec, Bool) async -> String?
  private let isPreview: Bool
  private let reader: Reader?
  private let writer: Writer?
  private let verificationDelay: UInt64
  private var revisions: [String: UInt64] = [:]
  private var awakeTask: Task<Void, Never>?

  init(
    preview: Bool = false, reader: Reader? = nil, writer: Writer? = nil,
    verificationDelay: UInt64 = 350_000_000
  ) {
    self.reader = reader
    self.writer = writer
    self.verificationDelay = verificationDelay
    isPreview = preview
    for spec in Catalog.all {
      states[spec.id] =
        preview
        ? ToggleState(
          isOn: spec.systemDefault || ["wifi", "bluetooth", "nightShift"].contains(spec.id),
          stale: false)
        : ToggleState()
    }
  }

  /// A separate in-memory model for interaction tests. No system reads or writes.
  static func preview(states: [String: ToggleState] = [:], awakeUntil: Date? = nil) -> ToggleEngine
  {
    let engine = ToggleEngine(preview: true)
    engine.states.merge(states) { _, value in value }
    engine.keepAwakeUntil = awakeUntil
    return engine
  }

  func state(_ id: String) -> ToggleState { states[id] ?? ToggleState() }

  // MARK: - Reading

  /// Reads one spec off the main actor. Pure with respect to app state.
  nonisolated static func read(_ spec: ToggleSpec, verifyingWrite: Bool = false) -> ToggleState {
    var st = ToggleState()
    st.stale = false

    switch spec.backend {
    case .defaults(let b):
      let value = Prefs.readBool(b, verifyingWrite: verifyingWrite)
      st.isOn = value ?? spec.systemDefault
      if verifyingWrite && value == nil { st.supported = false }

    case .multiDefaults(let backings):
      guard !backings.isEmpty else {
        st.supported = false
        return st
      }
      let values = backings.map { Prefs.readBool($0, verifyingWrite: verifyingWrite) }
      st.isOn = values[0] ?? spec.systemDefault
      if verifyingWrite && values.contains(where: { $0 == nil || $0 != st.isOn }) {
        st.supported = false
      }

    case .shell(let readCmd, _, _, let parse):
      let r = Shell.run(readCmd, timeout: 5)
      let parsed = (parse ?? Parse.truthy)(r)
      if let parsed {
        st.isOn = parsed
      } else if !verifyingWrite && !spec.unsupportedIfUnreadable
        && Self.isMissingPreference(command: readCmd, result: r)
      {
        st.isOn = spec.systemDefault
      } else if verifyingWrite || spec.unsupportedIfUnreadable || !r.ok {
        // -1 launch failure, -2 timeout: the command never produced an answer.
        st.supported = false
        st.isOn = spec.systemDefault
      } else {
        st.isOn = spec.systemDefault
      }

    case .bridge(let bridge):
      // Read first, then ask about support: the Bluetooth bridge answers
      // both from a single subprocess, and asking the other way round
      // would spawn it twice.
      let bridges = Bridges.shared
      if let v = bridges.read(bridge), bridges.supported(bridge) {
        st.isOn = v
      } else {
        st.supported = false
      }
    }
    return st
  }

  /// An absent defaults key is the documented system default, not missing hardware.
  nonisolated static func isMissingPreference(command: String, result: ShellResult) -> Bool {
    command.hasPrefix("/usr/bin/defaults read ") && result.status == 1
      && result.err.contains("does not exist")
  }

  /// True when the spec's read touches only in-process CFPreferences and can
  /// therefore run synchronously without measurable cost.
  private nonisolated static func isCheapRead(_ spec: ToggleSpec) -> Bool {
    switch spec.backend {
    case .defaults, .multiDefaults: return true
    case .bridge(let b): return b != .bluetooth
    case .shell: return false
    }
  }

  /// A read begun before a write must never replace the write's verified value.
  nonisolated static func acceptsRead(startedAt: UInt64, current: UInt64, busy: Bool) -> Bool {
    startedAt == current && !busy
  }

  func refreshAll() async {
    guard !isPreview else { return }
    guard !isRefreshing else { return }
    isRefreshing = true
    defer { isRefreshing = false }
    let started = revisions
    let cheap = reader == nil ? Catalog.all.filter { Self.isCheapRead($0) } : []
    let costly = Catalog.all.filter { spec in !cheap.contains { $0.id == spec.id } }

    for spec in cheap where !state(spec.id).busy {
      var value = Self.read(spec)
      value.error = state(spec.id).error
      states[spec.id] = value
    }

    let reader = self.reader
    await withTaskGroup(of: (String, ToggleState).self) { group in
      for spec in costly {
        group.addTask {
          let value: ToggleState
          if let reader { value = await reader(spec, false) } else { value = Self.read(spec) }
          return (spec.id, value)
        }
      }
      // Paint each result immediately. Bluetooth or a slow script must not
      // hold every other control in its initial loading state.
      for await (id, value) in group {
        guard
          Self.acceptsRead(
            startedAt: started[id, default: 0],
            current: revisions[id, default: 0], busy: state(id).busy)
        else { continue }
        var next = value
        next.error = state(id).error
        states[id] = next
      }
    }
    lastRefreshed = Date()
  }

  func refresh(_ id: String) async {
    guard !isPreview, let spec = Catalog.byID[id], !state(id).busy else { return }
    let revision = revisions[id, default: 0]
    let reader = self.reader
    let value: ToggleState
    if let reader {
      value = await reader(spec, false)
    } else {
      value = await Task.detached { Self.read(spec) }.value
    }
    guard
      Self.acceptsRead(
        startedAt: revision, current: revisions[id, default: 0],
        busy: state(id).busy)
    else { return }
    states[id] = value
  }

  /// Timed sessions live in this process and never survive quitting the app.
  func keepAwake(for duration: TimeInterval?) async {
    guard !state("keepAwake").busy else { return }
    if let duration, !duration.isFinite || duration <= 0 { return }
    await set("keepAwake", on: true)
    guard state("keepAwake").isOn, state("keepAwake").error == nil else { return }
    awakeTask?.cancel()
    keepAwakeUntil = duration.map { Date().addingTimeInterval($0) }
    guard let duration, let deadline = keepAwakeUntil else { return }
    awakeTask = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(duration)) } catch { return }
      guard let self else { return }
      while self.state("keepAwake").busy {
        do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
      }
      guard self.keepAwakeUntil == deadline, !Task.isCancelled else { return }
      await self.set("keepAwake", on: false)
    }
  }

  private func clearAwakeDeadline() {
    awakeTask?.cancel()
    awakeTask = nil
    keepAwakeUntil = nil
  }

  // MARK: - Writing

  func set(_ id: String, on: Bool) async {
    guard let spec = Catalog.byID[id] else { return }
    if isPreview {
      var value = state(id)
      guard value.supported, !value.busy, !value.stale else { return }
      value.isOn = on
      states[id] = value
      if id == "keepAwake" { clearAwakeDeadline() }
      return
    }
    var st = state(id)
    guard st.supported, !st.stale else { return }
    // One write per toggle at a time. Without this, a double-click on Keep
    // Awake starts two `caffeinate` processes — both see "not running", the
    // second overwrites the handle to the first, and the orphan holds its
    // power assertion for the life of the login session, so the Mac never
    // sleeps again. It also let two opposite writes race through separate
    // shells with nondeterministic ordering.
    guard !st.busy else { return }

    revisions[id, default: 0] += 1

    // Show the new position immediately; correct it if the write is rejected.
    let previous = st.isOn
    st.isOn = on
    st.busy = true
    st.error = nil
    states[id] = st

    let outcome: String?
    if let writer {
      outcome = await writer(spec, on)
    } else {
      outcome = await Task.detached { Self.performWrite(spec, on: on) }.value
    }

    if let failure = outcome {
      var s = state(id)
      s.isOn = previous
      s.busy = false
      s.error = failure
      revisions[id, default: 0] += 1
      states[id] = s
      bannerControlID = id
      banner = "\(spec.title): \(failure)"
      return
    }

    scheduleRestarts(spec.restarts)

    // Re-read to confirm. Preference daemons and pmset apply asynchronously,
    // so give them a moment before checking.
    try? await Task.sleep(nanoseconds: verificationDelay)
    let verified: ToggleState
    if let reader {
      verified = await reader(spec, true)
    } else {
      verified = await Task.detached { Self.read(spec, verifyingWrite: true) }.value
    }

    var s = verified
    s.busy = false
    if let error = Self.verificationError(spec, requested: on, actual: verified) {
      s.error = error
      bannerControlID = id
      banner = "\(spec.title): \(s.error ?? "the change did not stick.")"
    }
    revisions[id, default: 0] += 1
    states[id] = s
    if s.error == nil, bannerControlID == id {
      banner = nil
      bannerControlID = nil
    }
    if id == "keepAwake", s.error == nil { clearAwakeDeadline() }
  }

  nonisolated static func verificationError(
    _ spec: ToggleSpec, requested: Bool, actual: ToggleState
  ) -> String? {
    guard actual.supported else {
      return "Could not confirm the change. Refresh the control or check System Settings."
    }
    return actual.isOn == requested ? nil : rejectionReason(spec)
  }

  /// Same write path the switches use, exposed for the `--set` CLI.
  nonisolated static func performWriteForCLI(_ spec: ToggleSpec, on: Bool) -> String? {
    performWrite(spec, on: on)
  }

  /// Returns nil on success, or a message describing the failure.
  private nonisolated static func performWrite(_ spec: ToggleSpec, on: Bool) -> String? {
    switch spec.backend {
    case .defaults(let b):
      return runWrite(
        Prefs.writeCommand(b, on: on), spec: spec,
        allowsMissingPreference: b.value.writeLiteral(on: on) == nil)

    case .multiDefaults(let backings):
      let cmd = backings.map { Prefs.writeCommand($0, on: on) }.joined(separator: " && ")
      return runWrite(cmd, spec: spec)

    case .shell(_, let onCmd, let offCmd, _):
      return runWrite(on ? onCmd : offCmd, spec: spec)

    case .bridge(let bridge):
      return Bridges.shared.write(bridge, on: on)
    }
  }

  private nonisolated static func runWrite(
    _ command: String, spec: ToggleSpec, allowsMissingPreference: Bool = false
  ) -> String? {
    let result: ShellResult
    if spec.needsAdmin {
      result = LowPowerAuthorization.run(
        command, reason: "ToggleDeck needs your password to change \(spec.title).")
    } else {
      result = Shell.run(command, timeout: 20)
    }
    if result.status == -3 { return "cancelled at the password prompt." }
    if result.status == -2 { return "the command timed out." }
    // Deleting an already absent key is successful; verification still reads it back.
    if allowsMissingPreference && Prefs.isMissingKeyError(result) {
      return nil
    }
    if !result.ok {
      // `.message` because failures report on stderr, which is now a
      // separate stream from the stdout the parsers read.
      return humanize(result.message, spec: spec)
    }
    return nil
  }

  /// `defaults` reports permission problems as "Could not write domain …",
  /// which tells the user nothing actionable.
  private nonisolated static func humanize(_ output: String, spec: ToggleSpec) -> String {
    if output.contains("Could not write domain") {
      if output.contains("/Containers/") || spec.requires.contains(.fullDisk) {
        return
          "this app keeps its settings in a sandbox container. Give ToggleDeck Full Disk Access in System Settings → Privacy & Security."
      }
      return "macOS refused the write to that preference domain."
    }
    if output.lowercased().contains("not permitted") || output.contains("Operation not permitted") {
      return
        "macOS blocked the change. Check ToggleDeck permissions in System Settings → Privacy & Security."
    }
    return output.isEmpty ? "the command failed." : output
  }

  private nonisolated static func rejectionReason(_ spec: ToggleSpec) -> String {
    if spec.requires.contains(.fullDisk) {
      return
        "macOS discarded the write. Give ToggleDeck Full Disk Access in System Settings → Privacy & Security."
    }
    if spec.requires.contains(.logout) {
      return "written, but macOS will not report the new value until you log out and back in."
    }
    return "macOS did not accept the change."
  }

  // MARK: - Service restarts

  /// Flipping five Dock switches in a row should relaunch the Dock once, not
  /// five times, so restarts are coalesced into a single trailing pass.
  private func scheduleRestarts(_ services: [Service]) {
    guard !services.isEmpty, AppSettings.shared.restartServices else { return }
    pendingRestarts.formUnion(services)

    // `DispatchWorkItem.cancel()` does not stop the block from running, so the
    // generation is what makes this trailing: a superseded pass fires, sees a
    // newer generation, and returns without spawning anything.
    restartWorkItem?.cancel()
    restartGeneration += 1
    let generation = restartGeneration
    let work = DispatchWorkItem { [weak self] in
      guard let self, self.restartGeneration == generation else { return }
      self.restartWorkItem = nil
      let due = self.pendingRestarts
      self.pendingRestarts.removeAll()
      guard !due.isEmpty else { return }
      let command = due.map(\.killCommand).joined(separator: "; ")
      Task.detached { Shell.run(command, timeout: 10) }
    }
    restartWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
  }

  /// Applies any queued restart immediately, e.g. before the app quits.
  ///
  /// This runs inline rather than on a detached task: termination does not wait
  /// for one, so a queued restart would otherwise be dropped.
  func flushRestarts() {
    restartWorkItem?.cancel()
    restartWorkItem = nil
    restartGeneration += 1
    guard !pendingRestarts.isEmpty else { return }
    let command = pendingRestarts.map(\.killCommand).joined(separator: "; ")
    pendingRestarts.removeAll()
    Shell.run(command, timeout: 5)
  }
}

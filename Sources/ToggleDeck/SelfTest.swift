import Foundation

/// Read-only audit of the catalog. Reports, per entry, whether the backing
/// store answered and what value it gave, plus a summary of anything this Mac
/// cannot support. Never writes.
@MainActor
enum SelfTest {

  /// `--out PATH` exists so the report can be captured from a LaunchServices
  /// launch (`open --args --selftest --out ...`). That matters for anything
  /// TCC-gated: TCC attributes a request to the responsible process, so a
  /// binary exec'd from a terminal is judged against the terminal's
  /// entitlements, not the app bundle's.
  ///
  /// Returns the process exit code: 1 for duplicate ids or an unwritable
  /// `--out`, 0 otherwise. Entries unavailable on this Mac are hardware
  /// dependent and never fail the run.
  static func run(verbose: Bool, out: String? = nil) -> Int32 {
    let (report, duplicates) = build(verbose: verbose)
    var code: Int32 = duplicates.isEmpty ? 0 : 1
    if let failure = deliver(report, to: out) {
      FileHandle.standardError.write(Data("could not write \(out ?? ""): \(failure)\n".utf8))
      code = 1
    }
    return code
  }

  /// Prints the report, or writes it to `path`. Returns the failure text.
  static func deliver(_ report: String, to path: String?) -> String? {
    guard let path else {
      print(report, terminator: "")
      return nil
    }
    do {
      try report.write(toFile: path, atomically: true, encoding: .utf8)
      return nil
    } catch {
      return error.localizedDescription
    }
  }

  static func duplicateIDs(in specs: [ToggleSpec]) -> [String] {
    var seen = Set<String>()
    return specs.filter { !seen.insert($0.id).inserted }.map(\.id)
  }

  private static func build(verbose: Bool) -> (report: String, duplicates: [String]) {
    var sink = ""
    func print(_ s: String = "") { sink += s + "\n" }

    let start = Date()
    var unsupported: [ToggleSpec] = []
    let duplicates = duplicateIDs(in: Catalog.all)
    let uniqueCount = Set(Catalog.all.map(\.id)).count
    var slow: [(String, TimeInterval)] = []

    var byCategory: [Category: [(ToggleSpec, ToggleState)]] = [:]

    for spec in Catalog.all {
      let t0 = Date()
      let st = ToggleEngine.read(spec)
      let dt = Date().timeIntervalSince(t0)
      if dt > 0.25 { slow.append((spec.id, dt)) }
      if !st.supported { unsupported.append(spec) }
      byCategory[spec.category, default: []].append((spec, st))
    }

    print("ToggleDeck self-test")
    print(String(repeating: "=", count: 72))
    print("catalog entries : \(Catalog.all.count)")
    print("categories      : \(Category.allCases.count)")
    print(
      "unique ids      : \(uniqueCount)\(duplicates.isEmpty ? "" : "  DUPLICATES: \(duplicates)")")
    print("unavailable here: \(unsupported.count)")
    print("elapsed         : \(String(format: "%.2fs", Date().timeIntervalSince(start)))")
    print("")

    if verbose {
      for cat in Category.allCases {
        guard let rows = byCategory[cat] else { continue }
        print("\(cat.rawValue)  (\(rows.count))")
        print(String(repeating: "-", count: 72))
        for (spec, st) in rows {
          let mark = !st.supported ? "  n/a" : (st.isOn ? "   ON" : "  off")
          let flags = spec.requires.badges.map(\.0).joined(separator: ",")
          print("\(mark)  \(spec.id.padding(toLength: 30, withPad: " ", startingAt: 0)) \(flags)")
        }
        print("")
      }
    }

    if !unsupported.isEmpty {
      print("Unavailable on this Mac:")
      for s in unsupported { print("  - \(s.id)  (\(s.title))") }
      print("")
    }

    if !slow.isEmpty {
      print("Reads slower than 250ms:")
      for (id, dt) in slow.sorted(by: { $0.1 > $1.1 }) {
        print("  - \(id): \(String(format: "%.0fms", dt * 1000))")
      }
      print("")
    }

    let metrics = DropdownLayout.Metrics(showDescriptions: false)
    let screen = DropdownLayout.layoutScreen?.visibleFrame ?? .zero
    let pinnedFlow = DropdownLayout.pack(
      Catalog.defaultPinned.compactMap { Catalog.byID[$0] }.map { .row($0) },
      showDescriptions: false)
    let fullFlow = DropdownLayout.pack(Catalog.all.map { .row($0) }, showDescriptions: false)
    print("Dropdown layout")
    print("  screen          : \(Int(screen.width)) x \(Int(screen.height)) pt")
    print(
      "  column height   : \(Int(DropdownLayout.availableHeight(metrics))) pt "
        + "(~\(Int(DropdownLayout.availableHeight(metrics) / metrics.rowHeight)) rows)")
    print("  max columns     : \(DropdownLayout.maxColumns(metrics))")
    print(
      "  pinned (\(Catalog.defaultPinned.count))     : \(pinnedFlow.columns.count) column(s) "
        + "@ \(Int(pinnedFlow.columnWidth))pt, scrolls=\(pinnedFlow.overflowed)")
    print(
      "  all (\(Catalog.all.count))       : \(fullFlow.columns.count) column(s) "
        + "@ \(Int(fullFlow.columnWidth))pt, scrolls=\(fullFlow.overflowed)")
    print("")

    print(
      "Bridges: bluetooth=\(Bridges.shared.bluetoothSupported()) "
        + "nightShift=\(Bridges.shared.nightShiftSupported()) "
        + "trueTone=\(Bridges.shared.trueToneSupported())")
    print(
      "Pinned by default: \(Catalog.defaultPinned.count) "
        + "(all resolve: \(Catalog.defaultPinned.allSatisfy { Catalog.byID[$0] != nil }))")

    return (sink, duplicates)
  }
}

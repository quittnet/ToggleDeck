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
  static func run(verbose: Bool) {
    var sink = ""
    func print(_ s: String = "") { sink += s + "\n" }

    defer {
      let args = CommandLine.arguments
      if let i = args.firstIndex(of: "--out"), i + 1 < args.count {
        try? sink.write(toFile: args[i + 1], atomically: true, encoding: .utf8)
      } else {
        Swift.print(sink, terminator: "")
      }
    }

    let start = Date()
    var unsupported: [ToggleSpec] = []
    var duplicates: [String] = []
    var seen = Set<String>()
    var slow: [(String, TimeInterval)] = []

    for spec in Catalog.all where !seen.insert(spec.id).inserted {
      duplicates.append(spec.id)
    }

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
      "unique ids      : \(seen.count)\(duplicates.isEmpty ? "" : "  DUPLICATES: \(duplicates)")")
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
  }
}

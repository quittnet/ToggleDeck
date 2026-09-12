import AppKit

// Bluetooth helper mode. The parent process re-executes this binary rather than
// calling IOBluetooth itself, because CoreBluetooth aborts instead of returning
// an error when TCC denies it. Keep this check first: it must not touch AppKit.
if CommandLine.arguments.contains("--bt-get") || CommandLine.arguments.contains("--bt-set") {
  exit(Bridges.runBluetoothHelper(CommandLine.arguments))
}

// `--selftest` reads every catalog entry and prints the result, then exits.
// It performs no writes, so it is safe to run against a live Mac and is the
// quickest way to spot a preference key that does not exist on this release.
if CommandLine.arguments.contains("--selftest") {
  SelfTest.run(verbose: CommandLine.arguments.contains("--verbose"))
  exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--render-dropdown"),
  i + 1 < CommandLine.arguments.count
{
  DropdownPreview.render(prefix: CommandLine.arguments[i + 1])
  exit(0)
}

if CommandLine.arguments.contains("--preview-dropdown")
  || Bundle.main.object(forInfoDictionaryKey: "ToggleDeckPreview") as? Bool == true
{
  DropdownPreview.run()
  exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--render"), i + 1 < CommandLine.arguments.count {
  RenderTest.run(prefix: CommandLine.arguments[i + 1])
  exit(0)
}

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--make-icon") {
  guard i + 1 < args.count else { exit(CLI.argumentError("--make-icon needs an output path.")) }
  exit(IconGenerator.run(output: args[i + 1]))
}
if let i = args.firstIndex(of: "--get") {
  guard i + 1 < args.count else { exit(CLI.argumentError("--get needs a setting id.")) }
  exit(CLI.get(args[i + 1]))
}
if let i = args.firstIndex(of: "--set") {
  guard i + 2 < args.count else {
    exit(CLI.argumentError("--set needs a setting id and a value."))
  }
  exit(CLI.set(args[i + 1], args[i + 2]))
}
if let i = args.firstIndex(of: "--list") {
  exit(CLI.list(i + 1 < args.count ? args[i + 1] : nil))
}
if args.contains("--help") || args.contains("-h") {
  exit(CLI.usage())
}

// Anything left over is a typo. Falling through to the menu bar app here would
// hide the mistake behind a process that only ends when the user quits it.
let appArgumentCount = args.firstIndex(of: "--diagnose-popover").map { $0 + 2 <= args.count ? 2 : 1 } ?? 0
if args.count - appArgumentCount > 1 {
  exit(
    CLI.argumentError("unrecognised arguments: \(args.dropFirst().joined(separator: " "))"))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

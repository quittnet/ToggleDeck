import AppKit

// Bluetooth helper mode. The parent process re-executes this binary rather than
// calling IOBluetooth itself, because CoreBluetooth aborts instead of returning
// an error when TCC denies it. Keep this check first: it must not touch AppKit.
if CommandLine.arguments.contains("--bt-get") || CommandLine.arguments.contains("--bt-set") {
  exit(Bridges.runBluetoothHelper(CommandLine.arguments))
}

// Anything the parser rejects is a typo. Falling through to the menu bar app
// would hide the mistake behind a process that only ends when the user quits it.
switch CLI.parse(Array(CommandLine.arguments.dropFirst())) {
case .invalid(let message): exit(CLI.argumentError(message))
case .help: exit(CLI.usage())
case .version: exit(CLI.version())
case .get(let id): exit(CLI.get(id))
case .set(let id, let value): exit(await CLI.set(id, value))
case .toggle(let id): exit(await CLI.toggle(id))
case .list(let filter): exit(CLI.list(filter))
case .status(let json): exit(CLI.status(json: json))
case .cursorColors(let value): exit(CLI.cursorColors(value))
// `--selftest` reads every catalog entry and prints the result, then exits.
// It performs no writes, so it is safe to run against a live Mac and is the
// quickest way to spot a preference key that does not exist on this release.
case .selfTest(let verbose, let out): exit(SelfTest.run(verbose: verbose, out: out))
case .makeIcon(let path): exit(IconGenerator.run(output: path))
case .render(let prefix):
  RenderTest.run(prefix: prefix)
  exit(0)
case .renderDropdown(let prefix):
  DropdownPreview.render(prefix: prefix)
  exit(0)
case .previewDropdown:
  DropdownPreview.run()
  exit(0)
case .menuBarApp:
  break
}

// A bundle built for previews starts the dropdown preview when launched bare.
if CommandLine.arguments.count == 1,
  Bundle.main.object(forInfoDictionaryKey: "ToggleDeckPreview") as? Bool == true
{
  DropdownPreview.run()
  exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

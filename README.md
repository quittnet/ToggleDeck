# ToggleDeck 2.2

A menu bar app with 20 everyday Mac settings. All 20 controls are pinned by default; Customize lets you remove and reorder them. Search covers only these 20 settings.

## Settings

| Category | Controls |
|---|---|
| Display | Dark Mode, Night Shift, True Tone |
| Sound & Connections | Wi-Fi, Bluetooth, Mute Sound |
| Power | Low Power Mode, Keep Awake |
| Dock & Desktop | Auto-Hide Dock, Show Recent Applications, Stage Manager, Show Icons on Desktop, Auto-Hide Menu Bar |
| Finder | Show Hidden Files, Show All File Extensions, Show Path Bar |
| Typing & Trackpad | Tap to Click, Natural Scrolling, Autocorrect |
| Screenshots | Screenshot Preview |

The 176 other controls from version 1 were removed, including developer tweaks, remote services, security overrides, legacy settings, the duplicate spelling switch, and the keyboard remapper that replaced unrelated mappings. Removing a control does not change its macOS preference. Use System Settings for options outside this list.

## Menu and upgrades

Click the menu bar icon to open or close the menu. Right-click for Customize, Refresh, and Quit. Search finds a retained control even when it is not pinned. The menu uses two balanced columns for all 20 controls, keeps each category together, and fits without scrolling on a 1280 × 800 display. Search results shrink to a single column. Entire rows are clickable, with visible hover and keyboard focus. Command-F focuses search, Command-R refreshes, and Escape clears search or closes the menu. Arrow keys move between controls; Space activates the focused control.

The default menu contains every retained control, in category order. Reset to Defaults restores all 20. Custom arrangements retain their order across launches. Retired IDs and duplicate pins are removed without changing system settings.

The new app icon is packaged from `AppIcon.png`. The installer includes the source artwork and all macOS icon sizes. `--regen-icon` rebuilds the icon from that artwork.

## Keep Awake

Keep Awake holds native display and idle-system power assertions for the lifetime of ToggleDeck. Turning it off releases them; macOS also releases process-owned assertions when ToggleDeck exits or crashes. It does not override deliberate sleep or a closed laptop lid.

Keep Awake is controlled by the menu bar app only. Command-line reads and writes for it return an error instead of claiming to control another process's session.

## Build and run

Requires macOS 14 or later and Swift 6 to build.

```sh
bash launch_toggle_deck.sh
bash stop_toggle_deck.sh
bash install.sh --no-login-item
```

The installer builds and verifies a staged bundle before replacing the installed app. It retains the previous bundle under `.backups/`. Existing login configuration is preserved when using `--no-login-item`.

## Checks

```sh
swift format format --in-place --recursive Sources Tests
bash check_toggle_deck.sh
```

The check script runs formatting lint, script syntax checks, 25 regression tests, and a release build with warnings treated as errors. The package uses Swift 6 concurrency checking.

Use `--preview-dropdown` for a separate window with simulated control states. `--render-dropdown /path/to/preview` exports light, dark, search, empty, and detailed views without changing Mac settings.

Tests cover grouped and custom menu layout, isolated preview controls, catalog and menu migration, explicit command-line values, unavailable verification, shell output and deadline handling, concurrent commands, and Keep Awake assertion ownership, rollback, and cleanup. They do not change real macOS settings.

## Command line

```sh
~/Applications/ToggleDeck.app/Contents/MacOS/ToggleDeck --list
~/Applications/ToggleDeck.app/Contents/MacOS/ToggleDeck --get darkMode
~/Applications/ToggleDeck.app/Contents/MacOS/ToggleDeck --set darkMode 1
~/Applications/ToggleDeck.app/Contents/MacOS/ToggleDeck --selftest --verbose
```

Accepted values are `1/0`, `true/false`, `on/off`, and `yes/no`. Invalid values are rejected before writing. A write succeeds only after its value is read back; an unavailable read-back is an error. The read-only self-test checks availability and layout, not whether every switch changes system behavior.

A flag that is missing its value, or an argument ToggleDeck does not recognise, prints the usage text to stderr and exits 2. It does not fall through to the menu bar app.

macOS may request Automation or Bluetooth access when a control needs it. Low Power Mode requests administrator authorization. Some preferences require the affected service to restart or the user to log out, as indicated beside the control.

Night Shift and True Tone retain the existing private CoreBrightness integration, so availability can change with macOS updates.

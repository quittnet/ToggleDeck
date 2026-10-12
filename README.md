# ToggleDeck 2.7.0

A menu bar app with 23 everyday Mac switches, cursor controls, and a Sound dropdown. All switches are pinned by default; Customize lets you remove and reorder them. Search also finds cursor, pointer, fill, outline, color presets, pointer size, audio outputs, and saved combination names.

## Settings

| Category | Controls |
|---|---|
| Display | Dark Mode, Night Shift, True Tone, Reduce Motion, Reduce Transparency, Square Window Corners; cursor colors, pointer size, shake to find |
| Sound & Connections | Wi-Fi, Bluetooth, Mute Sound; audio output and volume |
| Power | Low Power Mode, Keep Awake |
| Dock & Desktop | Auto-Hide Dock, Show Recent Applications, Stage Manager, Show Icons on Desktop, Auto-Hide Menu Bar |
| Finder | Show Hidden Files, Show All File Extensions, Show Path Bar |
| Typing & Trackpad | Tap to Click, Natural Scrolling, Autocorrect |
| Screenshots | Screenshot Preview |

The earlier broad catalog was reduced to everyday controls, removing developer tweaks, remote services, security overrides, legacy settings, the duplicate spelling switch, and the keyboard remapper that replaced unrelated mappings. Removing a control does not change its macOS preference. Use System Settings for options outside this list.

## Menu and upgrades

Click the menu bar icon to open or close the menu. Right-click for Customize, Refresh, and Quit. Search finds a retained control even when it is not pinned. The menu uses two balanced columns for the available controls, keeps each category together, and adapts its column count and scrolling to the display. Search results shrink to a single column. Entire rows are clickable, with visible hover and keyboard focus. Command-F focuses search, Command-R refreshes, and Escape clears search or closes the menu. Arrow keys move between controls; Space activates the focused control.

The default menu contains every retained control, in category order. Reset to Defaults restores all 23. Custom arrangements retain their order across launches. Retired IDs and duplicate pins are removed without changing system settings.

The new app icon is packaged from `AppIcon.png`. The installer includes the source artwork and all macOS icon sizes. `--regen-icon` rebuilds the icon from that artwork.

## Version 2.3 improvements

- Search matches multiple words in any order, ignoring case, accents, and punctuation. `finder hidden`, `hidden finder`, and `wi fi` work in the menu, settings, and CLI.
- The search filter shows all on, off, or unavailable controls, including unpinned controls. Pin buttons in results add or remove a control immediately.
- Right-click a control for its description, pinning, refresh, and the corresponding System Settings pane. Errors include refresh and System Settings actions in both windows.
- The Power category's Timer menu starts Keep Awake for 15, 30, 60, or 120 minutes. An active session shows its remaining time, duration menu, Stop button, and a cup icon in the menu bar.
- Left and right arrow keys move between menu columns. Up and down move through controls, and scrolling keeps the focused row visible. Command-comma opens Customize.
- Customize includes up/down buttons as well as drag reordering. Moving a control switches off category grouping so the dropdown follows the saved order.
- Controls distinguish reading, applying, unavailable, and failed states. Reads arrive independently, and a refresh started before a write cannot overwrite its verified value.
- Desktop Icons preserves Finder's desktop menu and follows the automatic restart preference. An absent preference key reads as its system default; a failed read remains unavailable.

## Cursor colors

Open Cursor Color in the Display group to select Default, White, Red, Orange, Yellow, Green, Blue, Purple, or Pink. The Color Combinations group adds Fire, Ocean, Mint, Royal, and Candy, each with contrasting fill and outline colors. Presets apply immediately to the system pointer. Custom Colors opens a settings pane with separate fill and outline pickers, light/dark previews, an optional name, and Reset to Default.

Save Combination keeps the exact fill and outline in ToggleDeck's saved list without changing the pointer. Save & Apply saves and applies the pair. Saved combinations remain after restarting and appear in the dropdown and settings pane. Re-saving a pair with a new name renames it without creating a duplicate. The current custom system colors are saved automatically, including combinations chosen in Pointer Settings. Saving combinations locally does not require Full Disk Access or administrator authorization.

Cursor colors use guarded system functions also used by Accessibility settings. macOS protects these preferences: ToggleDeck needs Full Disk Access to save them. If a preset is rejected, the editor returns to the saved colors and the dropdown shows “Change not applied.” The app explains how to grant access and provides links to Full Disk Access and Pointer Settings. After granting access, quit and reopen ToggleDeck. Local builds are ad-hoc signed; a rebuild changes their code identity and can invalidate previous permission. If ToggleDeck is already enabled but writes fail after an update, remove it from Full Disk Access and add the current `~/Applications/ToggleDeck.app`, then restart it. Availability can change with macOS updates. Previews use isolated in-memory colors. The command line supports `--cursor-colors` for a JSON snapshot, `--cursor-colors blue` to apply a preset, and a snapshot as the argument to restore custom colors.

## New controls in 2.6

- Cursor settings include a 100–400% size slider, size presets, and Shake to Find Pointer. The cursor menu includes the same size presets and visibility toggle. These use macOS pointer settings and preserve saved color combinations. Size and visibility changes are confirmed against the saved preference file, so a cached value cannot hide a rejected write. If macOS denies access, the pane provides a Full Disk Access link and explains that ToggleDeck must be reopened.
- Sound opens an output-device picker and volume control. It changes the normal app audio output and preserves the separate alert output. Devices that control their own volume show that limitation instead of a working-looking slider. A Sound pane provides the same controls in settings.
- General includes a configurable global keyboard shortcut, enabled by default as Control–Option–Command–T. It opens or closes ToggleDeck from another app without Accessibility permission. Conflicting shortcuts are reported and the previous working shortcut is retained.
- Reduce Motion and Reduce Transparency are available in the Display category. A saved default menu adds these toggles on upgrade; custom menu order and intentional omissions are retained.

## New in 2.7: Square Window Corners

Square Window Corners appears in Display. On writes the global `NSConvolutionOverride1` preference as a float with value `1`; Off deletes the key to restore the macOS default. ToggleDeck reads the current preference at launch and verifies each change. Affected applications may need to restart before their corners update. ToggleDeck does not restart them automatically.

A saved default menu adds this control on upgrade. Custom menu order and intentional omissions are preserved; search or Customize can find and pin it. The command line supports `--get squareWindowCorners` and `--set squareWindowCorners 1` or `0`.

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

The check script runs formatting lint, script syntax checks, regression tests using Swift Testing, and a release build with warnings treated as errors. The package uses Swift 6 concurrency checking. The test suite uses Swift Testing and works with Command Line Tools installations that do not include XCTest.

Use `--preview-dropdown` for a separate window with simulated control states. `--render-dropdown /path/to/preview` exports light, dark, search, empty, detailed, loading, unavailable, error, and timed-session views without changing Mac settings.

Previews and rendering use isolated in-memory controls and do not change Mac settings. Tests cover search normalization, filters, keyboard navigation, timer expiry and replacement, refresh/write races, rollback, menu order persistence, grouped and custom menu layout, isolated preview controls, catalog and menu migration, explicit command-line values, unavailable verification, shell output and deadline handling, concurrent commands, and Keep Awake assertion ownership, rollback, and cleanup. They do not change real macOS settings.

## Command line

```sh
~/Applications/ToggleDeck.app/Contents/MacOS/ToggleDeck --list
~/Applications/ToggleDeck.app/Contents/MacOS/ToggleDeck --get darkMode
~/Applications/ToggleDeck.app/Contents/MacOS/ToggleDeck --set darkMode 1
~/Applications/ToggleDeck.app/Contents/MacOS/ToggleDeck --selftest --verbose
```

Accepted values are `1/0`, `true/false`, `on/off`, and `yes/no`. Invalid values are rejected before writing. A write succeeds only after its value is read back; an unavailable read-back is an error. The read-only self-test checks availability and layout, not whether every switch changes system behavior.

A flag that is missing its value, or an argument ToggleDeck does not recognise, prints the usage text to stderr and exits 2. It does not fall through to the menu bar app.

macOS may request Automation or Bluetooth access when a control needs it. Low Power Mode first tries the exact `pmset -a lowpowermode 0/1` commands through noninteractive sudo. If your account already permits those commands without a password, the toggle needs no prompt. Otherwise, it falls back to macOS administrator authorization. ToggleDeck does not create or modify sudo rules. Some preferences require the affected service to restart or the user to log out, as indicated beside the control.

Night Shift and True Tone retain the existing private CoreBrightness integration, so availability can change with macOS updates.

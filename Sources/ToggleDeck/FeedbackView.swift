import AppKit
import SwiftUI

@MainActor
struct FeedbackView: View {
  @ObservedObject var engine: ToggleEngine

  var body: some View {
    if let message = engine.banner {
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12))
          .foregroundStyle(DeckStyle.warning).accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 6) {
          Text(message).font(DeckStyle.value).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
          HStack(spacing: 2) {
            Button {
              Task { await engine.refreshAll(clearError: true) }
            } label: {
              Text("Refresh controls").padding(.horizontal, 5).frame(height: 24)
            }
            .disabled(engine.isRefreshing)
            Button {
              SystemSettingsLink.open()
            } label: {
              Text("System Settings…").padding(.horizontal, 5).frame(height: 24)
            }
          }
          .buttonStyle(DeckButtonStyle()).foregroundStyle(Color.accentColor)
          .font(DeckStyle.caption.weight(.medium))
          // Lines the button text up with the message despite the hover padding.
          .padding(.leading, -5)
        }
        Button {
          engine.banner = nil
        } label: {
          Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary).frame(width: 24, height: 24)
        }
        .buttonStyle(DeckButtonStyle()).accessibilityLabel("Dismiss message")
      }
      .padding(.leading, 10).padding(.trailing, 6).padding(.vertical, 9)
      // A tint of the warning hue rather than a fixed fill, so the banner
      // reads the same on the popover material and on a window background.
      .background(DeckStyle.warning.opacity(0.09), in: DeckStyle.card)
      .overlay { DeckStyle.card.strokeBorder(DeckStyle.warning.opacity(0.3), lineWidth: 1) }
    }
  }
}

enum SystemSettingsLink {
  /// Screenshots have no System Settings pane. Finder settings live in Finder.
  static func title(for spec: ToggleSpec) -> String? {
    switch spec.category {
    case .screenshots: return nil
    case .finder: return "Open Finder Settings…"
    default: return "Open System Settings…"
    }
  }

  @MainActor
  static func open(_ spec: ToggleSpec? = nil) {
    if spec?.category == .finder {
      openFinderSettings()
      return
    }
    if spec?.category == .screenshots { return }
    let pane: String
    switch spec?.category {
    case .display:
      pane =
        ["reduceMotion", "reduceTransparency"].contains(spec?.id ?? "")
        ? "com.apple.preference.universalaccess?Seeing_Display"
        : "com.apple.Displays-Settings.extension"
    case .connections:
      pane =
        spec?.id == "wifi"
        ? "com.apple.wifi-settings-extension"
        : spec?.id == "bluetooth"
          ? "com.apple.BluetoothSettings" : "com.apple.Sound-Settings.extension"
    case .power: pane = "com.apple.Battery-Settings.extension"
    case .desktop: pane = "com.apple.Desktop-Settings.extension"
    case .input:
      pane =
        spec?.id == "autoCorrect"
        ? "com.apple.Keyboard-Settings.extension" : "com.apple.Trackpad-Settings.extension"
    default: pane = ""
    }
    guard let url = URL(string: "x-apple.systempreferences:\(pane)") else { return }
    NSWorkspace.shared.open(url)
  }

  /// Runs off the main actor: an Apple Event blocks until macOS's consent
  /// dialog is answered or the event times out, and run in-process that
  /// froze the dropdown and the settings window for the whole wait.
  @MainActor
  private static func openFinderSettings() {
    let activate = Shell.quote("tell application \"Finder\" to activate")
    let keystroke = Shell.quote(
      "tell application \"System Events\" to keystroke \",\" using command down")
    let command = "/usr/bin/osascript -e \(activate) -e \(keystroke)"
    Task.detached {
      let result = Shell.run(command, timeout: 30)
      guard !result.ok else { return }
      await MainActor.run {
        _ = NSWorkspace.shared.open(
          URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
      }
    }
  }
}

@MainActor
struct ControlContextMenu: View {
  let spec: ToggleSpec
  @ObservedObject var engine: ToggleEngine
  @ObservedObject var settings: AppSettings

  var body: some View {
    Text(spec.menuTitle)
    if !spec.detail.isEmpty { Text(spec.detail) }
    Divider()
    if spec.id == "keepAwake" {
      AwakeDurationActions(engine: engine)
      Divider()
    }
    Button(settings.isPinned(spec.id) ? "Remove from Menu" : "Add to Menu") {
      settings.togglePin(spec.id)
    }
    Button("Refresh This Control") { Task { await engine.refresh(spec.id) } }
    if let title = SystemSettingsLink.title(for: spec) {
      Button(title) { SystemSettingsLink.open(spec) }
    }
  }
}

@MainActor
struct AwakeDurationActions: View {
  @ObservedObject var engine: ToggleEngine

  var body: some View {
    Group {
      ForEach([15, 30, 60, 120], id: \.self) { minutes in
        Button("Keep awake for \(minutes) minutes") {
          Task { await engine.keepAwake(for: Double(minutes) * 60) }
        }
      }
      Button("Keep awake until quit") { Task { await engine.keepAwake(for: nil) } }
      if engine.state("keepAwake").isOn {
        Button("Stop Keep Awake") { Task { await engine.set("keepAwake", on: false) } }
      }
    }.disabled(
      engine.state("keepAwake").busy || engine.state("keepAwake").stale
        || !engine.state("keepAwake").supported)
  }
}

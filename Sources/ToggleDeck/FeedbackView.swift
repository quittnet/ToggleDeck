import AppKit
import SwiftUI

@MainActor
struct FeedbackView: View {
  @ObservedObject var engine: ToggleEngine

  var body: some View {
    if let message = engine.banner {
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
          Text(message).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
          Button {
            engine.banner = nil
          } label: {
            Image(systemName: "xmark")
          }
          .buttonStyle(.plain).accessibilityLabel("Dismiss message")
        }
        HStack(spacing: 14) {
          Button("Refresh controls") { Task { await engine.refreshAll() } }
            .disabled(engine.isRefreshing)
          Button("System Settings…") { SystemSettingsLink.open() }
        }
        .buttonStyle(DeckButtonStyle()).foregroundStyle(Color.accentColor).font(.system(size: 11))
      }
      .padding(12)
      .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
      .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.orange.opacity(0.4)) }
    }
  }
}

enum SystemSettingsLink {
  static func open(_ spec: ToggleSpec? = nil) {
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
    Button("Open System Settings…") { SystemSettingsLink.open(spec) }
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

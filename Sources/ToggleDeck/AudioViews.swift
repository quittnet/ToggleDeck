import AppKit
import SwiftUI

@MainActor
struct AudioMenuRow: View {
  @ObservedObject var audio: AudioController
  var snapshot = false
  var onOpenSettings: () -> Void = {}
  /// Set by the dropdown while keyboard focus is on this row.
  var isFocused = false
  @ViewState<Bool> private var showing = false

  var body: some View {
    Group {
      if snapshot {
        label
      } else {
        Button {
          showing.toggle()
        } label: {
          label
        }
        .buttonStyle(DeckRowButtonStyle(isFocused: isFocused))
        // A plain button takes key focus only with Full Keyboard Access on,
        // and the dropdown's arrow keys have to land here without it.
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
          showing.toggle()
          return .handled
        }
        .popover(isPresented: $showing, arrowEdge: .trailing) {
          AudioControls(audio: audio) {
            showing = false
            onOpenSettings()
          }
        }
      }
    }
    .frame(height: DropdownLayout.audioRowHeight)
    .accessibilityLabel("Sound: \(audio.summary)")
    .accessibilityHint("Choose an output device and adjust its volume.")
    .help(audio.error ?? audio.summary)
    .task { await audio.refresh(clearError: false) }
  }

  private var label: some View {
    DeckValueRowLabel(
      title: "Sound", value: audio.summary, isBusy: audio.isApplying, snapshot: snapshot
    ) {
      IconTile(
        symbol: audio.isMuted == true ? "speaker.slash.fill" : "speaker.wave.2.fill",
        tint: Category.connections.tint, isLit: false)
    }
  }

  static func openSystemSoundSettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")
    else {
      return
    }
    NSWorkspace.shared.open(url)
  }
}

/// Output device and volume. The popover shows them stacked; the settings
/// pane shows each in its own section.
@MainActor
struct AudioControls: View {
  @ObservedObject var audio: AudioController
  var inPane = false
  var onOpenSettings: (() -> Void)?
  @ViewState<Double> private var draftVolume = 0
  @ViewState<Bool> private var editingVolume = false
  @ViewState<String?> private var editingUID = nil
  @ViewState<Task<Void, Never>?> private var pendingCommit = nil

  static let popoverWidth: CGFloat = 300
  private let paneInset = DeckStyle.cardInset

  private var busy: Bool { audio.isLoading || audio.isApplying }
  private var outputsLocked: Bool {
    busy || !audio.available || !audio.snapshot.canSelectOutput
  }
  private var volumePercent: String {
    guard audio.volume != nil else { return "Device volume" }
    return "\(Int((draftVolume * 100).rounded()))%"
  }

  var body: some View {
    Group {
      if inPane { paneBody } else { popoverBody }
    }
    .onAppear { draftVolume = audio.volume ?? 0 }
    .onChange(of: audio.volume) { _, value in
      if !editingVolume { draftVolume = value ?? 0 }
    }
    .onChange(of: audio.snapshot.selectedUID) { _, _ in
      pendingCommit?.cancel()
      editingVolume = false
      editingUID = nil
      draftVolume = audio.volume ?? 0
    }
    .onDisappear { pendingCommit?.cancel() }
  }

  private var popoverBody: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Sound").font(DeckStyle.cardTitle).accessibilityAddTraits(.isHeader)
        Spacer()
        AudioRefreshButton(audio: audio)
      }

      VStack(alignment: .leading, spacing: 4) {
        DeckSectionLabel(title: "Output")
        outputList(rowHeight: 26, highlightInset: 0)
          .padding(.horizontal, -DeckActionButtonStyle.textInset)
      }

      DeckSeparator(leadingInset: 0)

      volumeControls(showTitle: true)

      if let error = audio.error {
        DeckSeparator(leadingInset: 0)
        errorNotice(error)
      }

      if let onOpenSettings {
        DeckSeparator(leadingInset: 0)
        Button("Sound Settings…", action: onOpenSettings)
          .buttonStyle(DeckActionButtonStyle())
          .padding(.horizontal, -DeckActionButtonStyle.textInset)
      }
    }
    .padding(14)
    .frame(width: Self.popoverWidth)
  }

  private var paneBody: some View {
    VStack(alignment: .leading, spacing: DeckStyle.paneSpacing) {
      PaneSection(title: "Output Device") {
        outputList(rowHeight: 36, highlightInset: 3)
          .padding(.horizontal, paneInset - DeckActionButtonStyle.textInset - 3)
          .padding(.vertical, 4)
      }
      PaneSection(title: "Volume") {
        volumeControls(showTitle: false).padding(paneInset)
      }
      if let error = audio.error {
        errorNotice(error).padding(paneInset).deckCard()
      }
    }
  }

  @ViewBuilder
  private func outputList(rowHeight: CGFloat, highlightInset: CGFloat) -> some View {
    if audio.outputs.isEmpty {
      Text(audio.isLoading ? "Reading output devices…" : "No output devices connected.")
        .font(DeckStyle.value).foregroundStyle(.secondary)
        .padding(.horizontal, DeckActionButtonStyle.textInset + highlightInset)
        .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
    } else {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(audio.outputs) { output in
          let selected = output.uid == audio.snapshot.selectedUID
          Button {
            guard !selected else { return }
            Task { await audio.selectOutput(output.uid) }
          } label: {
            HStack(spacing: 8) {
              Text(output.name)
              Spacer(minLength: 8)
              Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .opacity(selected ? 1 : 0).accessibilityHidden(true)
            }
          }
          .buttonStyle(DeckActionButtonStyle(minHeight: rowHeight, highlightInset: highlightInset))
          .accessibilityAddTraits(selected ? .isSelected : [])
        }
      }
      .disabled(outputsLocked)
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Sound output device")
    }
  }

  private func volumeControls(showTitle: Bool) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      if showTitle || audio.isMuted == true {
        HStack(spacing: 6) {
          if showTitle { DeckSectionLabel(title: "Volume") }
          if audio.isMuted == true {
            Text("Muted").font(DeckStyle.caption).foregroundStyle(.secondary)
          }
          Spacer()
          if showTitle { percentLabel }
        }
      }
      HStack(spacing: 8) {
        Image(systemName: "speaker.fill").font(DeckStyle.value).foregroundStyle(.secondary)
          .frame(width: 14).accessibilityHidden(true)
        // No `step:`: on macOS it draws one tick mark per step. The binding
        // rounds instead, so the committed precision stays at 1%.
        Slider(value: volumeBinding, in: 0...1, onEditingChanged: volumeEditingChanged)
          .disabled(busy || !audio.canSetVolume)
          .accessibilityLabel("Output volume")
          .accessibilityValue(volumePercent)
        Image(systemName: "speaker.wave.3.fill").font(DeckStyle.value).foregroundStyle(.secondary)
          .frame(width: 20).accessibilityHidden(true)
        if !showTitle {
          percentLabel.frame(minWidth: 40, alignment: .trailing)
        }
      }
      if !audio.isLoading && audio.available && !audio.canSetVolume {
        Text("Adjust volume on this device.").font(DeckStyle.caption).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else if audio.isMuted == true {
        Text("Changing volume keeps mute on.").font(DeckStyle.caption).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private var percentLabel: some View {
    Text(volumePercent).font(DeckStyle.value).monospacedDigit().foregroundStyle(.secondary)
      .lineLimit(1)
  }

  private func errorNotice(_ error: String) -> some View {
    DeckNotice(message: error) {
      Button("Refresh") { Task { await audio.refresh() } }
        .disabled(audio.isRefreshing || audio.isApplying)
      Button("System Sound Settings…") { AudioMenuRow.openSystemSoundSettings() }
    }
  }

  private var volumeBinding: Binding<Double> {
    Binding(
      get: { draftVolume },
      set: { value in
        draftVolume = (value * 100).rounded() / 100
        // Native Slider sends editing boundaries for drags. Debounce keyboard/accessibility changes.
        if !editingVolume { commitVolume(after: .milliseconds(150)) }
      })
  }

  private func volumeEditingChanged(_ editing: Bool) {
    pendingCommit?.cancel()
    if editing {
      editingUID = audio.snapshot.selectedUID
      editingVolume = true
    } else {
      let unchangedOutput = editingUID == audio.snapshot.selectedUID
      editingVolume = false
      editingUID = nil
      if unchangedOutput { commitVolume(after: .zero) }
    }
  }

  private func commitVolume(after delay: Duration) {
    pendingCommit?.cancel()
    let value = draftVolume
    let uid = audio.snapshot.selectedUID
    pendingCommit = Task { @MainActor in
      if delay != .zero { try? await Task.sleep(for: delay) }
      guard !Task.isCancelled, !editingVolume, audio.snapshot.selectedUID == uid else { return }
      await audio.setVolume(value)
      // A rejected or snapped-back write leaves audio.volume unchanged, so
      // onChange never fires; resync here unless the user is dragging again.
      if !editingVolume { draftVolume = audio.volume ?? 0 }
    }
  }
}

private struct AudioRefreshButton: View {
  @ObservedObject var audio: AudioController

  var body: some View {
    Button {
      Task { await audio.refresh() }
    } label: {
      if audio.isRefreshing || audio.isLoading {
        ProgressView().controlSize(.small)
      } else {
        Image(systemName: "arrow.clockwise")
      }
    }
    .buttonStyle(.borderless).disabled(audio.isRefreshing || audio.isApplying)
    .help("Refresh sound devices and volume").accessibilityLabel("Refresh sound")
  }
}

@MainActor
struct AudioPane: View {
  @ObservedObject var audio: AudioController

  var body: some View {
    PaneScaffold {
      PaneHeader(title: "Sound", subtitle: "The output this Mac plays through, and its volume.") {
        AudioRefreshButton(audio: audio)
      }
      AudioControls(audio: audio, inPane: true)
      VStack(alignment: .leading, spacing: 8) {
        Button("Open System Sound Settings…") { AudioMenuRow.openSystemSoundSettings() }
        Text("Choose a connected output and set its volume. Mute is controlled by Mute Sound.")
          .font(DeckStyle.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .task { await audio.refresh(clearError: false) }
  }
}

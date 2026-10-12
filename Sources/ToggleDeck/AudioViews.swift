import AppKit
import SwiftUI

@MainActor
struct AudioMenuRow: View {
  @ObservedObject var audio: AudioController
  var snapshot = false
  var onOpenSettings: () -> Void = {}
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
        .buttonStyle(DeckRowButtonStyle())
        .popover(isPresented: $showing, arrowEdge: .trailing) {
          AudioControls(audio: audio) {
            showing = false
            onOpenSettings()
          }.padding(16).frame(width: 330)
        }
      }
    }
    .frame(height: 40)
    .accessibilityLabel("Sound: \(audio.summary)")
    .accessibilityHint("Choose an output device and adjust its volume.")
    .help(audio.error ?? audio.summary)
    .task { await audio.refresh(clearError: false) }
  }

  private var label: some View {
    HStack(spacing: 10) {
      Image(systemName: audio.isMuted == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
        .font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
        .frame(width: 22).accessibilityHidden(true)
      Text("Sound").font(.system(size: 13, weight: .medium))
      Spacer(minLength: 6)
      if audio.isApplying && !snapshot { ProgressView().controlSize(.small) }
      Text(audio.summary).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
      Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.secondary).accessibilityHidden(true)
    }
    .padding(.horizontal, 10).frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
  }

  static func openSystemSoundSettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")
    else {
      return
    }
    NSWorkspace.shared.open(url)
  }
}

@MainActor
private struct AudioControls: View {
  @ObservedObject var audio: AudioController
  var showTitle = true
  var onOpenSettings: (() -> Void)?
  @ViewState<Double> private var draftVolume = 0
  @ViewState<Bool> private var editingVolume = false
  @ViewState<String?> private var editingUID = nil
  @ViewState<Task<Void, Never>?> private var pendingCommit = nil

  private var busy: Bool { audio.isLoading || audio.isApplying }
  private var volumePercent: String {
    guard audio.volume != nil else { return "Device volume" }
    return "\(Int((draftVolume * 100).rounded()))%"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if showTitle {
        HStack {
          Text("Sound").font(.system(size: 15, weight: .semibold))
          Spacer()
          refreshButton
        }
      }

      if audio.outputs.isEmpty {
        Text(audio.isLoading ? "Reading output devices…" : "No output devices connected.")
          .font(.system(size: 12)).foregroundStyle(.secondary)
      } else {
        Picker("Output", selection: outputBinding) {
          if audio.snapshot.selectedUID == nil { Text("Choose an output").tag("") }
          ForEach(audio.outputs) { output in
            Text(output.name).tag(output.uid)
          }
        }
        .pickerStyle(.menu)
        .disabled(busy || !audio.available || !audio.snapshot.canSelectOutput)
        .accessibilityLabel("Sound output device")
      }

      VStack(spacing: 6) {
        HStack {
          Text("Volume").font(.system(size: 12, weight: .medium))
          if audio.isMuted == true {
            Text("Muted").font(.system(size: 11)).foregroundStyle(.secondary)
          }
          Spacer()
          Text(volumePercent).font(.system(size: 11.5)).monospacedDigit().foregroundStyle(
            .secondary)
        }
        HStack(spacing: 9) {
          Image(systemName: "speaker.fill").foregroundStyle(.secondary).accessibilityHidden(true)
          Slider(
            value: volumeBinding, in: 0...1, step: 0.01, onEditingChanged: volumeEditingChanged
          )
          .disabled(busy || !audio.canSetVolume)
          .accessibilityLabel("Output volume")
          .accessibilityValue(volumePercent)
          Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
        if !audio.isLoading && audio.available && !audio.canSetVolume {
          Text("Adjust volume on this device.").font(.system(size: 11)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if audio.isMuted == true {
          Text("Changing volume keeps mute on.").font(.system(size: 11)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }

      if let error = audio.error {
        VStack(alignment: .leading, spacing: 8) {
          Label(error, systemImage: "exclamationmark.circle.fill")
            .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
          HStack {
            Button("Refresh") { Task { await audio.refresh() } }
              .disabled(audio.isRefreshing || audio.isApplying)
            Button("System Sound Settings…") { AudioMenuRow.openSystemSoundSettings() }
          }.font(.system(size: 11.5))
        }
      }

      if let onOpenSettings {
        Divider()
        Button("Sound Settings…", action: onOpenSettings).font(.system(size: 12))
      } else if !showTitle {
        HStack {
          Spacer()
          refreshButton
        }
      }
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

  private var refreshButton: some View {
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

  private var outputBinding: Binding<String> {
    Binding(
      get: { audio.snapshot.selectedUID ?? "" },
      set: { uid in Task { await audio.selectOutput(uid) } })
  }

  private var volumeBinding: Binding<Double> {
    Binding(
      get: { draftVolume },
      set: { value in
        draftVolume = value
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
    }
  }
}

@MainActor
struct AudioPane: View {
  @ObservedObject var audio: AudioController

  var body: some View {
    Form {
      Section("Output Device & Volume") {
        AudioControls(audio: audio, showTitle: false)
      }
      Section {
        Button("Open System Sound Settings…") { AudioMenuRow.openSystemSoundSettings() }
        Text("Choose a connected output and set its volume. Mute is controlled by Mute Sound.")
          .font(.system(size: 11)).foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .task { await audio.refresh(clearError: false) }
  }
}

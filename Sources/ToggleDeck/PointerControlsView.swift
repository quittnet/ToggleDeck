import SwiftUI

@MainActor
struct PointerControlsView: View {
  @ObservedObject var pointer: PointerController
  @ViewState<Double> private var draftScale = 1
  @ViewState<Bool> private var isDragging = false
  @ViewState<Task<Void, Never>?> private var pendingChange = nil

  private var canEdit: Bool { pointer.available && !pointer.isLoading && !pointer.isApplying }
  private var draftLabel: String { "\(Int((draftScale * 100).rounded()))%" }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Pointer size").font(.system(size: 13, weight: .medium))
        Spacer()
        if pointer.isLoading {
          Text("Reading…").font(.system(size: 12)).foregroundStyle(.secondary)
        } else if !pointer.available {
          Text("Unavailable").font(.system(size: 12)).foregroundStyle(.secondary)
        } else if pointer.isApplying {
          ProgressView().controlSize(.small)
        } else {
          Menu(draftLabel) {
            ForEach([1.0, 1.25, 1.5, 2, 3, 4], id: \.self) { scale in
              Button("\(Int(scale * 100))%") { requestScale(scale) }
            }
          }.menuStyle(.borderlessButton).fixedSize().disabled(!canEdit)
            .accessibilityLabel("Pointer size: \(draftLabel)")
        }
      }
      Slider(
        value: Binding(
          get: { draftScale },
          set: { value in
            draftScale = value
            if !isDragging { scheduleKeyboardScale(value) }
          }),
        in: PointerSettings.supportedScale, step: 0.05
      ) { editing in
        isDragging = editing
        cancelPendingChange()
        if !editing { requestScale(draftScale) }
      }
      .disabled(!canEdit).accessibilityLabel("Pointer size")
      .accessibilityValue(draftLabel)
      .help("Adjust your Mac’s pointer size. Changes apply when you finish dragging.")
      Toggle(
        "Shake pointer to locate",
        isOn: Binding(
          get: { pointer.settings.shakeToFind },
          set: { enabled in
            cancelPendingChange()
            let scale = draftScale
            Task { @MainActor in
              await pointer.apply(PointerSettings(scale: scale, shakeToFind: enabled))
              draftScale = pointer.settings.scale
            }
          })
      )
      .toggleStyle(.switch).font(.system(size: 13)).disabled(!canEdit)
      .help("Quickly move your mouse or finger on the trackpad to enlarge the pointer briefly.")
      if let error = pointer.error {
        VStack(alignment: .leading, spacing: 7) {
          Label(error, systemImage: "exclamationmark.circle.fill")
            .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
          HStack(spacing: 12) {
            Button("Refresh") { Task { await pointer.refresh() } }
              .disabled(pointer.isRefreshing || pointer.isApplying)
            Button("Full Disk Access…") { CursorColorMenu.openFullDiskAccess() }
            Button("Pointer Settings…") { CursorColorMenu.openPointerSettings() }
          }.font(.system(size: 12))
        }
      }
    }
    .frame(maxWidth: 330)
    .onAppear { draftScale = pointer.settings.scale }
    .onChange(of: pointer.settings) { old, new in
      if !isDragging, !old.matches(new) {
        cancelPendingChange()
        draftScale = new.scale
      }
    }
    .onDisappear { cancelPendingChange() }
    .task { await pointer.refresh(clearError: false) }
  }

  private func requestScale(_ scale: Double) {
    guard canEdit else { return }
    cancelPendingChange()
    draftScale = scale
    Task { @MainActor in await applyScale(scale) }
  }

  private func cancelPendingChange() {
    pendingChange?.cancel()
    pendingChange = nil
  }

  private func scheduleKeyboardScale(_ scale: Double) {
    // Only slider input schedules a delay. Updating the draft after a preset or
    // a confirmed native change must not cancel or duplicate a running commit.
    guard canEdit else { return }
    cancelPendingChange()
    guard abs(scale - pointer.settings.scale) > 0.0001 else { return }
    pendingChange = Task { @MainActor in
      do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
      guard !Task.isCancelled, !isDragging else { return }
      pendingChange = nil
      await applyScale(scale)
    }
  }

  private func applyScale(_ scale: Double) async {
    await pointer.apply(PointerSettings(scale: scale, shakeToFind: pointer.settings.shakeToFind))
    draftScale = pointer.settings.scale
  }
}
